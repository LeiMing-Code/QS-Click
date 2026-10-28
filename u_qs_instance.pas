unit u_qs_instance;

{
  QS Click - защита от запуска второй копии приложения.

  Первая копия создаёт именованный мьютекс. Если мьютекс уже существует,
  вторая копия не запускает приложение, а широковещательным сообщением
  просит первую копию показать главное окно.

  Сообщение принимает скрытое окно значка в области уведомлений
  (u_qs_tray). Регистрация сообщения выполняется функцией
  QSRegisterActivationMessage.
}

{$WARN SYMBOL_PLATFORM OFF}

interface

uses
  Winapi.Windows;

const
  { Имя действует в пределах текущего сеанса пользователя: две копии
    в разных сеансах (например, через быстрое переключение пользователей)
    друг другу не мешают. }
  QSInstanceMutexName = 'Local\QS Click-8E2B4E43-6A2D-4F62-9B1D-2A7C4D51F0B8';
  QSInstanceMessageName = 'QS Click-Activate-8E2B4E43-6A2D-4F62-9B1D-2A7C4D51F0B8';

var
  /// <summary>Зарегистрированное сообщение активации (0, пока не зарегистрировано).</summary>
  QSActivateMessage: UINT = 0;

/// <summary>
/// Пытается стать единственной копией приложения.
/// Возвращает False, если приложение уже запущено.
/// </summary>
function QSAcquireSingleInstance: Boolean;

/// <summary>Освобождает мьютекс единственной копии.</summary>
procedure QSReleaseSingleInstance;

/// <summary>
/// Регистрирует широковещательное сообщение активации.
/// Вызывается из модуля значка в области уведомлений.
/// </summary>
procedure QSRegisterActivationMessage;

/// <summary>
/// Просит уже запущенную копию показать главное окно.
/// Используется второй копией перед завершением.
/// </summary>
procedure QSActivateExistingInstance;

implementation

const
  { Winapi.Windows не объявляет ASFW_ANY; значение взято из документации
    Windows SDK (AllowSetForegroundWindow(-1)). }
  QSAsfwAny = DWORD($FFFFFFFF);

var
  GInstanceMutex: THandle = 0;

function QSAcquireSingleInstance: Boolean;
begin
  if GInstanceMutex <> 0 then
    Exit(True);

  { CreateMutex не сбрасывает LastError при успешном создании нового
    мьютекса, поэтому обнуляем его перед вызовом. }
  SetLastError(0);
  GInstanceMutex := CreateMutex(nil, False, QSInstanceMutexName);
  if GInstanceMutex = 0 then
  begin
    { Если мьютекс создать не удалось, не мешаем работе приложения. }
    Result := True;
    Exit;
  end;

  if GetLastError = ERROR_ALREADY_EXISTS then
  begin
    CloseHandle(GInstanceMutex);
    GInstanceMutex := 0;
    Result := False;
  end
  else
    Result := True;
end;

procedure QSReleaseSingleInstance;
begin
  if GInstanceMutex <> 0 then
  begin
    CloseHandle(GInstanceMutex);
    GInstanceMutex := 0;
  end;
end;

procedure QSRegisterActivationMessage;
begin
  if QSActivateMessage = 0 then
    QSActivateMessage := RegisterWindowMessage(PChar(QSInstanceMessageName));
end;

procedure QSActivateExistingInstance;
var
  I: Integer;
begin
  QSRegisterActivationMessage;
  if QSActivateMessage = 0 then
    Exit;

  { Разрешаем первой копии выйти на передний план. }
  AllowSetForegroundWindow(QSAsfwAny);

  { Первая копия могла ещё создавать окно значка. Несколько попыток
    повышают шанс, что сообщение будет доставлено. }
  for I := 1 to 5 do
  begin
    PostMessage(HWND_BROADCAST, QSActivateMessage, 0, 0);
    Sleep(80);
  end;
end;

end.
