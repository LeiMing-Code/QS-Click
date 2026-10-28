unit u_qs_tray;

{
  QS Click - значок в области уведомлений и глобальные горячие клавиши.

  Реализовано на Win32 API (Shell_NotifyIcon + AllocateHWnd), без сторонних
  компонентов. FireMonkey не содержит готового TTrayIcon, поэтому используется
  нативное скрытое окно-получатель сообщений.

  Комбинации по умолчанию:
    Ctrl+Shift+1 - снимок области;
    Ctrl+Shift+2 - снимок активного окна;
    Ctrl+Shift+3 - снимок всего рабочего стола.

  Комбинации можно переназначить; актуальный набор передаётся из
  u_qs_settings при запуске и после сохранения настроек.
}

{$WARN SYMBOL_PLATFORM OFF}

interface

uses
  Winapi.Windows,
  u_qs_settings;

type
  TQSTrayAction = (
    qstaCaptureRegion,
    qstaCaptureWindow,
    qstaCaptureDesktop,
    qstaCaptureMonitor,
    qstaShowMain,
    qstaSettings,
    qstaExit
  );

  TQSTrayActionEvent = procedure(AAction: TQSTrayAction; AIndex: Integer) of object;

/// <summary>
/// Создаёт значок в трее, скрытое окно сообщений и регистрирует горячие
/// клавиши из AHotkeys. AOnAction вызывается в главном потоке при выборе
/// пункта меню, нажатии горячей клавиши или запросе второй копии приложения.
/// AIndex используется только для qstaCaptureMonitor.
/// </summary>
procedure QSTrayInitialize(AOnAction: TQSTrayActionEvent;
  const AHotkeys: TQSHotkeys);

/// <summary>Удаляет значок, снимает горячие клавиши и освобождает окно.</summary>
procedure QSTrayFinalize;

/// <summary>Задаёт количество мониторов для подменю "Снимок монитора".</summary>
procedure QSTraySetMonitorCount(ACount: Integer);

/// <summary>Показывает всплывающее уведомление возле значка.</summary>
procedure QSTrayShowBalloon(const ATitle, AText: string);

/// <summary>
/// Заменяет набор глобальных комбинаций. Если хотя бы одну комбинацию
/// заняла другая программа, возвращает False и восстанавливает прежний набор.
/// </summary>
function QSTrayApplyHotkeys(const AHotkeys: TQSHotkeys): Boolean;

/// <summary>Временно снимает глобальные комбинации (на время окна настроек).</summary>
procedure QSTraySuspendHotkeys;

/// <summary>Возвращает глобальные комбинации после временного снятия.</summary>
/// <returns>False, если хотя бы одну комбинацию заняла другая программа.</returns>
function QSTrayResumeHotkeys: Boolean;

/// <summary>
/// True, если набор глобальных комбинаций сейчас зарегистрирован и работает.
/// После неудачной замены QSTrayApplyHotkeys восстанавливает прежний набор;
/// эта функция показывает, удалось ли его вернуть.
/// </summary>
function QSTrayHotkeysActive: Boolean;

/// <summary>
/// Описание последней комбинации, которую не удалось зарегистрировать:
/// "Ctrl+Shift+1 (вероятно, комбинацию использует: ShareX)". Пустая строка,
/// если конфликтов не было.
/// </summary>
function QSTrayLastHotkeyConflict: string;

/// <summary>Создан ли значок и окно сообщений.</summary>
function QSTrayReady: Boolean;

implementation

uses
  System.SysUtils,
  System.Classes,
  Winapi.Messages,
  Winapi.ShellAPI,
  u_qs_instance;

const
  WM_QS_TRAY = WM_APP + 37;

  HOTKEY_REGION = 1;
  HOTKEY_WINDOW = 2;
  HOTKEY_DESKTOP = 3;

  HOTKEY_IDS: array[TQSHotkeyKind] of Integer = (
    HOTKEY_REGION,
    HOTKEY_WINDOW,
    HOTKEY_DESKTOP
  );

  ID_CAPTURE_REGION = 1001;
  ID_CAPTURE_WINDOW = 1002;
  ID_CAPTURE_DESKTOP = 1003;
  ID_MONITOR_BASE = 1100;
  ID_SHOW_MAIN = 1200;
  ID_SETTINGS = 1201;
  ID_EXIT = 1202;

type
  TQSTray = class
  private
    FWnd: HWND;
    FIconData: TNotifyIconData;
    FOnAction: TQSTrayActionEvent;
    FMonitorCount: Integer;
    FIconAdded: Boolean;
    FHotkeys: TQSHotkeys;
    FHotkeysSuspended: Boolean;
    FHotkeysRegistered: Boolean;
    FLastConflictValid: Boolean;
    FLastConflict: TQSHotkey;
    FLastConflictOwner: string;
    procedure WndProc(var AMessage: TMessage);
    procedure AddIcon;
    procedure RemoveIcon;
    function RegisterHotkeys: Boolean;
    procedure UnregisterHotkeys;
    procedure SuspendHotkeys;
    function ResumeHotkeys: Boolean;
    function SetHotkeys(const AHotkeys: TQSHotkeys): Boolean;
    function MenuCaption(const ACaption: string;
      AKind: TQSHotkeyKind): string;
    procedure ShowMenu;
    procedure DoAction(AAction: TQSTrayAction; AIndex: Integer);
  public
    constructor Create(AOnAction: TQSTrayActionEvent;
      const AHotkeys: TQSHotkeys);
    destructor Destroy; override;
  end;

var
  GTray: TQSTray = nil;

{ ------------------------------------------------------------------ }
{ Вспомогательные функции                                            }
{ ------------------------------------------------------------------ }

procedure QSCopyToWideBuffer(var ABuffer: array of WideChar;
  const AText: string);
begin
  if Length(ABuffer) = 0 then
    Exit;
  StrLCopy(PWideChar(@ABuffer[0]), PWideChar(AText), Length(ABuffer) - 1);
end;

function QSMonitorCaption(AIndex: Integer): string;
begin
  Result := Format('Монитор %d', [AIndex + 1]);
end;

{ ------------------------------------------------------------------ }
{ TQSTray                                                            }
{ ------------------------------------------------------------------ }

constructor TQSTray.Create(AOnAction: TQSTrayActionEvent;
  const AHotkeys: TQSHotkeys);
begin
  inherited Create;
  FOnAction := AOnAction;
  FMonitorCount := 0;
  FIconAdded := False;
  FHotkeys := AHotkeys;
  FHotkeysSuspended := False;
  FHotkeysRegistered := False;
  FLastConflictValid := False;
  FLastConflict.Modifiers := 0;
  FLastConflict.VirtualKey := 0;
  FLastConflictOwner := '';

  FWnd := AllocateHWnd(WndProc);
  if FWnd = 0 then
    Exit;

  { Оболочка Explorer работает с обычным уровнем целостности. Если
    QS Click запущен от администратора, UIPI блокирует её сообщения
    нашему окну, и значок в трее перестаёт реагировать на мышь.
    Разрешаем собственное сообщение трея и сообщение активации. }
  ChangeWindowMessageFilter(WM_QS_TRAY, MSGFLT_ADD);

  QSRegisterActivationMessage;
  if QSActivateMessage <> 0 then
    ChangeWindowMessageFilter(QSActivateMessage, MSGFLT_ADD);

  FillChar(FIconData, SizeOf(FIconData), 0);
  FIconData.cbSize := SizeOf(TNotifyIconData);
  FIconData.Wnd := FWnd;
  FIconData.uID := 1;
  FIconData.uFlags := NIF_MESSAGE or NIF_ICON or NIF_TIP;
  FIconData.uCallbackMessage := WM_QS_TRAY;
  FIconData.hIcon := LoadIcon(HInstance, 'MAINICON');
  if FIconData.hIcon = 0 then
    FIconData.hIcon := LoadIcon(0, IDI_APPLICATION);
  QSCopyToWideBuffer(FIconData.szTip, QSAppTitle);

  AddIcon;
  RegisterHotkeys;
end;

destructor TQSTray.Destroy;
begin
  UnregisterHotkeys;
  RemoveIcon;
  if FWnd <> 0 then
  begin
    DeallocateHWnd(FWnd);
    FWnd := 0;
  end;
  inherited Destroy;
end;

procedure TQSTray.AddIcon;
begin
  if (FWnd = 0) or FIconAdded then
    Exit;
  FIconAdded := Shell_NotifyIcon(NIM_ADD, @FIconData);
end;

procedure TQSTray.RemoveIcon;
begin
  if (FWnd = 0) or not FIconAdded then
    Exit;
  Shell_NotifyIcon(NIM_DELETE, @FIconData);
  FIconAdded := False;
end;

function TQSTray.RegisterHotkeys: Boolean;
var
  K: TQSHotkeyKind;
  H: TQSHotkey;
begin
  Result := True;
  FHotkeysRegistered := False;
  if FHotkeysSuspended then
    Exit;
  if FWnd = 0 then
    Exit(False);

  for K := Low(TQSHotkeyKind) to High(TQSHotkeyKind) do
  begin
    H := FHotkeys[K];
    if not QSHotkeyIsValid(H) then
      Continue;

    if not RegisterHotKey(FWnd, HOTKEY_IDS[K], H.Modifiers, H.VirtualKey) then
    begin
      { Запоминаем комбинацию и best-effort подсказку о владельце, чтобы
        показать её в сообщении при сохранении настроек. }
      FLastConflictValid := True;
      FLastConflict := H;
      FLastConflictOwner := QSHotkeyOwnerHint(H);

      { Не оставляем частично назначенный набор. }
      UnregisterHotkeys;
      Exit(False);
    end;
  end;

  FHotkeysRegistered := True;
end;

procedure TQSTray.UnregisterHotkeys;
var
  K: TQSHotkeyKind;
begin
  FHotkeysRegistered := False;
  if FWnd = 0 then
    Exit;
  for K := Low(TQSHotkeyKind) to High(TQSHotkeyKind) do
    UnregisterHotKey(FWnd, HOTKEY_IDS[K]);
end;

procedure TQSTray.SuspendHotkeys;
begin
  if FHotkeysSuspended then
    Exit;
  UnregisterHotkeys;
  FHotkeysSuspended := True;
end;

function TQSTray.ResumeHotkeys: Boolean;
begin
  if not FHotkeysSuspended then
    Exit(FHotkeysRegistered);
  FHotkeysSuspended := False;
  Result := RegisterHotkeys;
end;

function TQSTray.SetHotkeys(const AHotkeys: TQSHotkeys): Boolean;
var
  OldHotkeys: TQSHotkeys;
begin
  { Новый конфликт должен относиться именно к последней попытке. }
  FLastConflictValid := False;
  FLastConflict.Modifiers := 0;
  FLastConflict.VirtualKey := 0;
  FLastConflictOwner := '';

  OldHotkeys := FHotkeys;
  UnregisterHotkeys;
  FHotkeys := AHotkeys;
  Result := RegisterHotkeys;

  if not Result then
  begin
    { Не оставляем приложение с частично назначенными комбинациями:
      возвращаем прежний рабочий набор. }
    UnregisterHotkeys;
    FHotkeys := OldHotkeys;
    RegisterHotkeys;
  end;
end;

function TQSTray.MenuCaption(const ACaption: string;
  AKind: TQSHotkeyKind): string;
begin
  Result := ACaption;
  if QSHotkeyIsValid(FHotkeys[AKind]) then
    Result := Result + #9 + QSHotkeyText(FHotkeys[AKind]);
end;

procedure TQSTray.DoAction(AAction: TQSTrayAction; AIndex: Integer);
begin
  if Assigned(FOnAction) then
    FOnAction(AAction, AIndex);
end;

procedure TQSTray.ShowMenu;
var
  MainMenu, MonitorMenu: HMENU;
  Cmd: UINT;
  P: TPoint;
  I: Integer;
  ItemText: string;
begin
  if FWnd = 0 then
    Exit;

  MainMenu := CreatePopupMenu;
  if MainMenu = 0 then
    Exit;

  try
    ItemText := MenuCaption('Снимок области', qshkRegion);
    AppendMenu(MainMenu, MF_STRING, ID_CAPTURE_REGION, PChar(ItemText));
    ItemText := MenuCaption('Активное окно', qshkWindow);
    AppendMenu(MainMenu, MF_STRING, ID_CAPTURE_WINDOW, PChar(ItemText));
    ItemText := MenuCaption('Весь рабочий стол', qshkDesktop);
    AppendMenu(MainMenu, MF_STRING, ID_CAPTURE_DESKTOP, PChar(ItemText));

    if FMonitorCount > 0 then
    begin
      MonitorMenu := CreatePopupMenu;
      if MonitorMenu <> 0 then
      begin
        for I := 0 to FMonitorCount - 1 do
        begin
          ItemText := QSMonitorCaption(I);
          AppendMenu(MonitorMenu, MF_STRING, ID_MONITOR_BASE + UINT_PTR(I),
            PChar(ItemText));
        end;
        AppendMenu(MainMenu, MF_POPUP, UINT_PTR(MonitorMenu),
          PChar('Снимок монитора'));
      end;
    end;

    AppendMenu(MainMenu, MF_SEPARATOR, 0, nil);
    AppendMenu(MainMenu, MF_STRING, ID_SHOW_MAIN,
      PChar('Открыть ' + QSAppCaption));
    AppendMenu(MainMenu, MF_STRING, ID_SETTINGS, PChar('Настройки...'));
    AppendMenu(MainMenu, MF_STRING, ID_EXIT, PChar('Выход'));

    GetCursorPos(P);
    SetForegroundWindow(FWnd);
    Cmd := UINT(TrackPopupMenu(MainMenu,
      TPM_RETURNCMD or TPM_RIGHTBUTTON or TPM_LEFTALIGN or TPM_TOPALIGN,
      P.X, P.Y, 0, FWnd, nil));
    PostMessage(FWnd, WM_NULL, 0, 0);

    if (Cmd >= ID_MONITOR_BASE) and (Cmd < ID_MONITOR_BASE + UINT(FMonitorCount)) then
      DoAction(qstaCaptureMonitor, Integer(Cmd - ID_MONITOR_BASE))
    else
      case Cmd of
        ID_CAPTURE_REGION: DoAction(qstaCaptureRegion, -1);
        ID_CAPTURE_WINDOW: DoAction(qstaCaptureWindow, -1);
        ID_CAPTURE_DESKTOP: DoAction(qstaCaptureDesktop, -1);
        ID_SHOW_MAIN: DoAction(qstaShowMain, -1);
        ID_SETTINGS: DoAction(qstaSettings, -1);
        ID_EXIT: DoAction(qstaExit, -1);
      end;
  finally
    DestroyMenu(MainMenu);
  end;
end;

procedure TQSTray.WndProc(var AMessage: TMessage);
var
  MouseMessage: UINT;
  P: TPoint;
begin
  { Вторая копия приложения просит показать главное окно. }
  if (QSActivateMessage <> 0) and (AMessage.Msg = QSActivateMessage) then
  begin
    DoAction(qstaShowMain, -1);
    AMessage.Result := 0;
    Exit;
  end;

  if AMessage.Msg = WM_QS_TRAY then
  begin
    MouseMessage := UINT(AMessage.LParam) and $FFFF;

    case MouseMessage of
      WM_LBUTTONUP, WM_LBUTTONDBLCLK:
        DoAction(qstaShowMain, -1);
      WM_RBUTTONUP, WM_CONTEXTMENU:
        ShowMenu;
      NIN_BALLOONUSERCLICK:
        DoAction(qstaShowMain, -1);
    end;

    AMessage.Result := 0;
    Exit;
  end;

  if AMessage.Msg = WM_HOTKEY then
  begin
    case AMessage.WParam of
      HOTKEY_REGION: DoAction(qstaCaptureRegion, -1);
      HOTKEY_WINDOW: DoAction(qstaCaptureWindow, -1);
      HOTKEY_DESKTOP: DoAction(qstaCaptureDesktop, -1);
    end;
    AMessage.Result := 0;
    Exit;
  end;

  { Для сообщений, которые не относятся к трею, вызываем стандартную обработку. }
  if (AMessage.Msg = WM_RBUTTONDOWN) or (AMessage.Msg = WM_LBUTTONDOWN) then
  begin
    GetCursorPos(P);
    SetForegroundWindow(FWnd);
  end;

  AMessage.Result := DefWindowProc(FWnd, AMessage.Msg,
    AMessage.WParam, AMessage.LParam);
end;

{ ------------------------------------------------------------------ }
{ Публичный интерфейс                                                }
{ ------------------------------------------------------------------ }

procedure QSTrayInitialize(AOnAction: TQSTrayActionEvent;
  const AHotkeys: TQSHotkeys);
begin
  if GTray <> nil then
    Exit;
  GTray := TQSTray.Create(AOnAction, AHotkeys);
end;

procedure QSTrayFinalize;
begin
  if GTray <> nil then
  begin
    GTray.Free;
    GTray := nil;
  end;
end;

procedure QSTraySetMonitorCount(ACount: Integer);
begin
  if GTray <> nil then
    GTray.FMonitorCount := ACount;
end;

procedure QSTrayShowBalloon(const ATitle, AText: string);
var
  NID: TNotifyIconData;
begin
  if (GTray = nil) or (GTray.FWnd = 0) or not GTray.FIconAdded then
    Exit;

  NID := GTray.FIconData;
  NID.uFlags := NIF_INFO;
  QSCopyToWideBuffer(NID.szInfoTitle, ATitle);
  QSCopyToWideBuffer(NID.szInfo, AText);
  NID.dwInfoFlags := NIIF_INFO;
  NID.uTimeout := 5000;
  Shell_NotifyIcon(NIM_MODIFY, @NID);
end;

function QSTrayApplyHotkeys(const AHotkeys: TQSHotkeys): Boolean;
begin
  if GTray = nil then
    Exit(False);
  Result := GTray.SetHotkeys(AHotkeys);
end;

procedure QSTraySuspendHotkeys;
begin
  if GTray <> nil then
    GTray.SuspendHotkeys;
end;

function QSTrayResumeHotkeys: Boolean;
begin
  if GTray = nil then
    Exit(True);
  Result := GTray.ResumeHotkeys;
end;

function QSTrayHotkeysActive: Boolean;
begin
  Result := (GTray <> nil) and GTray.FHotkeysRegistered;
end;

function QSTrayLastHotkeyConflict: string;
begin
  Result := '';
  if (GTray = nil) or not GTray.FLastConflictValid then
    Exit;

  Result := QSHotkeyText(GTray.FLastConflict);
  if GTray.FLastConflictOwner <> '' then
    Result := Result + ' (' + GTray.FLastConflictOwner + ')'
  else
    Result := Result + ' (занята другой программой или Windows)';
end;

function QSTrayReady: Boolean;
begin
  Result := (GTray <> nil) and (GTray.FWnd <> 0) and GTray.FIconAdded;
end;

end.
