unit u_qs_settings;

{
  QS Click - настройки приложения и отдельное окно настроек.

  Модуль отвечает за:
    * хранение параметров в %USERPROFILE%\QS Click\settings.ini;
    * перенос старых настроек из %USERPROFILE%\QS-Click и
      %USERPROFILE%\QuickScreen;
    * глобальные горячие клавиши (запись, проверка, текст комбинации);
    * автозапуск через HKCU\Software\Microsoft\Windows\CurrentVersion\Run;
    * окно "Настройки" с навигацией слева и страницами справа;
    * страницу "О программе" на основе Markdown4D.Fmx.Viewer (Win32).

  Просмотрщик Markdown4D включён для Win32 по умолчанию. Для Win64 его нет,
  поэтому там используется обычный TMemo. Если пакет Markdown4D недоступен
  компилятору, добавьте в условные символы проекта QS_NO_MARKDOWN4D —
  страница "О программе" будет показывать текст about.md в TMemo.

  Окно настроек строится программно, без .fmx-файла. Изменения применяются
  только после нажатия "Сохранить": главное окно получает копию настроек
  через свойство Settings.
}

{$WARN SYMBOL_PLATFORM OFF}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.UITypes,
  System.Math,
  System.IOUtils,
  System.IniFiles,
  System.Win.Registry,
  Winapi.Windows,
  Winapi.ShellAPI,
  Winapi.TlHelp32,
  { ВАЖНО: Winapi.Windows объявляет TBitmap = tagBITMAP.
    FMX.Graphics должен идти после Winapi.Windows. }
  FMX.Types,
  FMX.Controls,
  FMX.Forms,
  FMX.Graphics,
  FMX.Dialogs,
  FMX.StdCtrls,
  FMX.Objects,
  FMX.Edit,
  FMX.ListBox,
  FMX.TabControl,
  FMX.Memo
  { Просмотрщик Markdown4D подключается для Win32. Символ QS_NO_MARKDOWN4D
    оставляет страницу "О программе" на обычном TMemo. }
  {$IF Defined(MSWINDOWS) and not Defined(WIN64) and not Defined(QS_NO_MARKDOWN4D)}
  , Markdown4D.Fmx.Viewer
  {$ENDIF}
  ;

const
  QSAppCaption = 'QS Click';
  QSAppTitle = 'QS Click - снимки экрана';
  QSAppVersion = '1.0.0';
  QSAppAuthor = '@Lei Ming';
  QSAppWebsite = 'www.leiming.ru';
  QSAppUrl = 'http://www.leiming.ru';

  { Имя папки данных отделено от отображаемого имени приложения,
    чтобы переименование в интерфейсе не ломало существующие настройки. }
  QSAppFolderName = 'QS Click';
  QSLegacyFolderName = 'QuickScreen';
  QSLegacyFolderName2 = 'QS-Click';

  QSAppIniFileName = 'settings.ini';
  QSAppIniSection = 'QS Click';
  QSLegacyIniSection = 'QS-Click';
  QSLegacyIniSection2 = 'QuickScreen';

  { Секция settings.ini с последними параметрами редактора снимков. }
  QSEditorIniSection = 'Editor';

  QSAboutFileBaseName = 'about.md';
  QSAutostartRegistryKey = 'Software\Microsoft\Windows\CurrentVersion\Run';
  QSAutostartValueName = 'QS Click';
  QSAutostartLegacyValueName = 'QS-Click';

type
  /// <summary>Формат сохранения снимка.</summary>
  TQSImageFormat = (qsifPng, qsifJpeg);

  /// <summary>Действие, для которого назначается глобальная комбинация.</summary>
  TQSHotkeyKind = (qshkRegion, qshkWindow, qshkDesktop);

  /// <summary>Глобальная горячая клавиша. Modifiers - набор MOD_* из Winapi.Windows.</summary>
  TQSHotkey = record
    Modifiers: Cardinal;
    VirtualKey: Word;
  end;

  TQSHotkeys = array[TQSHotkeyKind] of TQSHotkey;

  /// <summary>Все параметры приложения. Поля намеренно открыты: это простой DTO.</summary>
  TQSAppSettings = class(TPersistent)
  public
    SaveFolder: string;
    /// <summary>Последний каталог, в который пользователь сохранял снимок.
    /// Диалог «Сохранить» открывается в нём; пустая строка — используется
    /// SaveFolder. Обновляется при каждом успешном сохранении.</summary>
    LastSaveDir: string;
    SaveFormat: TQSImageFormat;
    JpegQuality: Integer;
    OpenEditorAfterCapture: Boolean;
    CopyAfterCapture: Boolean;
    MinimizeToTray: Boolean;
    ShowNotifications: Boolean;
    LastMonitorIndex: Integer;
    StartMinimized: Boolean;
    Autostart: Boolean;
    Hotkeys: TQSHotkeys;

    { Последние параметры редактора снимков. Живут в секции [Editor]
      файла settings.ini; редактор синхронизирует их при каждом
      изменении и сохраняет при закрытии окна. Значения по умолчанию
      совпадают с QSDefault* в u_qs_editor.pas. }
    EditorPenColor: TAlphaColor;
    EditorFillColor: TAlphaColor;
    EditorMarkerColor: TAlphaColor;
    EditorPenWidth: Integer;
    EditorFillOpacity: Integer;
    EditorTextSize: Integer;
    EditorTextFill: Boolean;
    EditorTextBorder: Boolean;
    EditorTextBorderWidth: Integer;
    EditorTextPadding: Integer;
    EditorArrowHead: Boolean;
    EditorMarkerOpacity: Integer;
    EditorMarkerPenWidth: Integer;
    EditorMarkerRoundCap: Boolean;
    EditorNumFillColor: TAlphaColor;
    EditorNumTextColor: TAlphaColor;
    EditorNumSize: Integer;
    EditorNumSquare: Boolean;

    constructor Create;
    procedure SetDefaults;
    procedure Assign(Source: TPersistent); override;

    /// <summary>Читает INI, при необходимости переносит старый файл.</summary>
    procedure Load;
    /// <summary>Записывает INI (ошибки записи не прерывают работу).</summary>
    procedure Save;

    procedure LoadFromIni(AIni: TCustomIniFile;
      const ASection, ALegacySection: string);
    procedure SaveToIni(AIni: TCustomIniFile; const ASection: string);
  end;

/// <summary>
/// Текущие настройки приложения. Глобальная ссылка нужна, чтобы другие модули
/// (например, редактор снимков) читали и обновляли тот же объект, что и главное
/// окно. Устанавливает главная форма при создании настроек и снимает перед
/// своим уничтожением.
/// </summary>
var
  QSGlobalSettings: TQSAppSettings = nil;

/// <summary>Папка приложения в профиле пользователя: %USERPROFILE%\QS Click.</summary>
function QSAppDataFolder: string;
/// <summary>Старая папка настроек: %USERPROFILE%\QuickScreen.</summary>
function QSLegacyAppDataFolder: string;
/// <summary>Полный путь к settings.ini.</summary>
function QSSettingsFileName: string;
/// <summary>Полный путь к about.md.</summary>
function QSAboutFileName: string;

/// <summary>Папка сохранения по умолчанию: «Изображения» текущего пользователя.</summary>
function QSDefaultSaveFolder: string;

/// <summary>Создаёт about.md с описанием программы, если файла ещё нет.</summary>
procedure QSEnsureAboutFile;

/// <summary>Включён ли автозапуск в HKCU (по наличию значения).</summary>
function QSAutostartEnabled: Boolean;
/// <summary>Включает или выключает автозапуск. False - ошибка доступа к реестру.</summary>
function QSSetAutostart(AEnabled: Boolean): Boolean;

/// <summary>Комбинация по умолчанию для действия.</summary>
function QSDefaultHotkey(AKind: TQSHotkeyKind): TQSHotkey;
/// <summary>Является ли клавиша модификатором (Ctrl, Alt, Shift, Win).</summary>
function QSIsModifierKey(AKey: Word): Boolean;
/// <summary>Комбинация содержит модификатор и обычную клавишу.</summary>
function QSHotkeyIsValid(const AHotkey: TQSHotkey): Boolean;
/// <summary>Совпадают ли две комбинации.</summary>
function QSHotkeysEqual(const A, B: TQSHotkey): Boolean;
/// <summary>Читаемый текст комбинации, например "Ctrl+Shift+1".</summary>
function QSHotkeyText(const AHotkey: TQSHotkey): string;
/// <summary>Текст только модификаторов, например "Ctrl+Shift+".</summary>
function QSHotkeyModifiersText(AModifiers: Cardinal): string;
/// <summary>Преобразует состояние Shift из FMX в набор MOD_*.</summary>
function QSModifiersFromShift(const AShift: TShiftState): Cardinal;
/// <summary>
/// Проверяет, можно ли сейчас зарегистрировать комбинацию (не занята ли она
/// другой программой). Регистрация сразу снимается.
/// </summary>
function QSHotkeyAvailableNow(const AHotkey: TQSHotkey): Boolean;
/// <summary>
/// Best-effort подсказка, какое запущенное приложение может удерживать
/// комбинацию. Windows не предоставляет API владельца RegisterHotKey,
/// поэтому вывод строится по списку известных программ с глобальными
/// клавишами. Пустая строка - определить не удалось.
/// </summary>
function QSHotkeyOwnerHint(const AHotkey: TQSHotkey): string;

type
  /// <summary>Модальное окно настроек QS Click.</summary>
  TQSSettingsForm = class(TForm)
  private
    FEditing: TQSAppSettings;

    FHeaderPanel: TPanel;
    FBottomPanel: TPanel;
    FBtnSave: TButton;
    FBtnCancel: TButton;

    FNav: TListBox;
    FTabs: TTabControl;

    FEdFolder: TEdit;
    FBtnBrowse: TButton;
    FCmbFormat: TComboBox;
    FQualityTrack: TTrackBar;
    FQualityValue: TLabel;

    FChkEditor: TCheckBox;
    FChkCopy: TCheckBox;
    FChkMinimizeToTray: TCheckBox;
    FChkStartMinimized: TCheckBox;
    FChkAutostart: TCheckBox;
    FChkNotifications: TCheckBox;

    FHotkeyEdits: array[TQSHotkeyKind] of TEdit;
    FHotkeyStatus: TLabel;

    FCapturing: Boolean;
    FCaptureKind: TQSHotkeyKind;

    procedure BuildUI;
    procedure BuildCapturesPage(APage: TTabItem);
    procedure BuildSavePage(APage: TTabItem);
    procedure BuildHotkeysPage(APage: TTabItem);
    procedure BuildBehaviorPage(APage: TTabItem);
    procedure BuildAboutPage(APage: TTabItem);
    procedure LoadValues;

    function NewLabel(AParent: TControl; const AText: string;
      AX, AY, AWidth, AHeight: Single; ABold: Boolean = False;
      AWordWrap: Boolean = False): TLabel;
    function NewButton(AParent: TControl; const AText: string;
      AX, AY, AWidth, AHeight: Single): TButton;
    function NewCheckBox(AParent: TControl; const AText: string;
      AX, AY, AWidth: Single): TCheckBox;
    function NewGroupBox(AParent: TControl; const AText: string;
      AX, AY, AWidth, AHeight: Single): TGroupBox;
    function AddPage(const ACaption: string): TTabItem;

    procedure UpdateQualityState;
    procedure UpdateHotkeyEdits;
    procedure SetHotkeyStatus(const AText: string; AError: Boolean);
    procedure BeginHotkeyCapture(AKind: TQSHotkeyKind);
    procedure EndHotkeyCapture;
    procedure SelectPage(AIndex: Integer);

    procedure NavChange(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure FormDeactivate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
    procedure btnBrowseClick(Sender: TObject);
    procedure cmbFormatChange(Sender: TObject);
    procedure tbQualityChange(Sender: TObject);
    procedure btnHotkeyClick(Sender: TObject);
    procedure btnResetHotkeysClick(Sender: TObject);
    procedure HotkeyEditExit(Sender: TObject);
    procedure HotkeyEditKeyDown(Sender: TObject; var Key: Word;
      var KeyChar: WideChar; Shift: TShiftState);
    procedure MarkdownLinkClick(const Sender: TObject; const AUrl: string);
    procedure AboutFooterClick(Sender: TObject);
    procedure OpenExternalUrl(const AUrl: string);
  public
    /// <summary>Заполняет окно копией переданных настроек.</summary>
    procedure Initialize(const ASettings: TQSAppSettings);
    /// <summary>Настройки, отредактированные в окне.</summary>
    property Settings: TQSAppSettings read FEditing;
  end;

implementation

const
  QSDefaultAboutText: array[0..57] of string = (
    '# QS Click',
    '',
    '**QS Click** - быстрые снимки экрана для Windows.',
    '',
    'Программа работает в области уведомлений и умеет снимать область,',
    'активное окно, весь рабочий стол и отдельный монитор. Снимок сразу',
    'можно отредактировать, скопировать в буфер обмена или сохранить',
    'в файл PNG/JPEG.',
    '',
    '## Основной функционал',
    '',
    '- снимок произвольной области с выделением мышью;',
    '- снимок активного окна, всего рабочего стола или отдельного монитора;',
    '- поддержка нескольких мониторов, в том числе с разным масштабом DPI;',
    '- встроенный редактор снимков:',
    '  - линия и стрелка с наконечником;',
    '  - текстовая подпись (фон, рамка, отступ, толщина рамки);',
    '  - прямоугольник и эллипс (контур, заливка, прозрачность);',
    '  - маркер - полупрозрачная подсветка (цвет, толщина, прозрачность);',
    '  - размытие выбранной области;',
    '  - нумератор - круг или квадрат с порядковым номером (цвет, размер);',
    '  - обрезка снимка до выделенной области;',
    '  - панель свойств активного инструмента справа;',
    '  - масштаб колесом мыши, кнопками и «1:1», прокрутка средней кнопкой;',
    '  - цвета из палитры, толщина линий;',
    '  - отмена и повтор (Ctrl+Z / Ctrl+Y, до 20 шагов);',
    '  - редактор запоминает последние параметры в settings.ini;',
    '- копирование в буфер обмена, сохранение в PNG/JPEG;',
    '- запоминание последней папки сохранения (settings.ini);',
    '- настраиваемые глобальные горячие клавиши;',
    '- автозапуск с Windows и одиночный экземпляр приложения.',
    '',
    '## Горячие клавиши (по умолчанию)',
    '',
    '| Действие | Комбинация |',
    '| --- | --- |',
    '| Снимок области | `Ctrl+Shift+1` |',
    '| Активное окно | `Ctrl+Shift+2` |',
    '| Весь рабочий стол | `Ctrl+Shift+3` |',
    '',
    '### В редакторе снимков',
    '',
    '| Действие | Комбинация |',
    '| --- | --- |',
    '| Сохранить | `Ctrl+S` |',
    '| Копировать | `Ctrl+C` |',
    '| Отменить / повторить | `Ctrl+Z` / `Ctrl+Y` |',
    '| Масштаб 1:1 | `Ctrl+0` |',
    '| Закрыть редактор | `Esc` |',
    '',
    'Комбинации снимков можно изменить в разделе **Настройки > Горячие клавиши**.',
    '',
    '## Автор',
    '',
    '@Lei Ming',
    '',
    'Сайт: [www.leiming.ru](http://www.leiming.ru)',
    ''
  );

{ ------------------------------------------------------------------ }
{ Пути и служебные файлы                                             }
{ ------------------------------------------------------------------ }

function QSAppDataFolder: string;
begin
  Result := System.IOUtils.TPath.Combine(
    System.IOUtils.TPath.GetHomePath, QSAppFolderName);
end;

function QSLegacyAppDataFolder: string;
begin
  Result := System.IOUtils.TPath.Combine(
    System.IOUtils.TPath.GetHomePath, QSLegacyFolderName);
end;

function QSSettingsFileName: string;
begin
  Result := System.IOUtils.TPath.Combine(QSAppDataFolder, QSAppIniFileName);
end;

function QSAboutFileName: string;
begin
  { about.md хранится рядом с исполняемым файлом программы. }
  Result := System.IOUtils.TPath.Combine(
    System.SysUtils.ExtractFilePath(ParamStr(0)), QSAboutFileBaseName);
end;

function QSDefaultSaveFolder: string;
begin
  { «Изображения» текущего пользователя. Если система не вернула путь,
    берём одноимённую папку в профиле. }
  Result := System.IOUtils.TPath.GetPicturesPath;
  if Trim(Result) = '' then
    Result := System.IOUtils.TPath.Combine(
      System.IOUtils.TPath.GetHomePath, 'Pictures');
end;

procedure QSEnsureSettingsMigrated;
var
  NewFile, Dir, LegacyDir, LegacyFile: string;
  Candidates: array[0..1] of string;
  I: Integer;
begin
  Dir := QSAppDataFolder;
  if not DirectoryExists(Dir) then
    ForceDirectories(Dir);

  NewFile := System.IOUtils.TPath.Combine(Dir, QSAppIniFileName);
  if FileExists(NewFile) then
    Exit;

  { Сначала ищем настройки предыдущего имени (QS-Click), затем самой
    первой версии (QuickScreen). }
  Candidates[0] := System.IOUtils.TPath.Combine(
    System.IOUtils.TPath.GetHomePath, QSLegacyFolderName2);
  Candidates[1] := QSLegacyAppDataFolder;

  for I := Low(Candidates) to High(Candidates) do
  begin
    LegacyDir := Candidates[I];
    if SameText(LegacyDir, Dir) then
      Continue;

    LegacyFile := System.IOUtils.TPath.Combine(LegacyDir, QSAppIniFileName);
    if FileExists(LegacyFile) then
    try
      System.IOUtils.TFile.Copy(LegacyFile, NewFile, False);
      Exit;
    except
      { Пробуем следующий вариант; если перенос не удался, настройки
        начнутся со значений по умолчанию. }
    end;
  end;
end;

procedure QSEnsureAboutFile;
var
  FileName: string;
  Lines: TStringList;
  I: Integer;
begin
  FileName := QSAboutFileName;

  { Если установщик уже положил about.md рядом с программой, его
    содержимое не перезаписываем. Иначе создаём файл из встроенного
    описания QSDefaultAboutText. }
  if not FileExists(FileName) then
  begin
    Lines := TStringList.Create;
    try
      for I := Low(QSDefaultAboutText) to High(QSDefaultAboutText) do
        Lines.Add(QSDefaultAboutText[I]);
      { Описание не критично для работы приложения. }
      try
        Lines.SaveToFile(FileName, TEncoding.UTF8);
      except
      end;
    finally
      Lines.Free;
    end;
  end;

  { Файл описания делаем скрытым и только для чтения — и когда его только
    что создала программа, и когда он поставлен установщиком (без
    атрибутов). Если файла нет (запись не удалась), ничего не трогаем. }
  if FileExists(FileName) then
    SetFileAttributes(PChar(FileName),
      FILE_ATTRIBUTE_HIDDEN or FILE_ATTRIBUTE_READONLY);
end;

{ ------------------------------------------------------------------ }
{ Автозапуск                                                         }
{ ------------------------------------------------------------------ }

function QSAutostartEnabled: Boolean;
var
  Reg: TRegistry;
begin
  Result := False;
  try
    Reg := TRegistry.Create;
    try
      Reg.RootKey := HKEY_CURRENT_USER;
      if Reg.OpenKeyReadOnly(QSAutostartRegistryKey) then
        Result := Reg.ValueExists(QSAutostartValueName) or
          Reg.ValueExists(QSAutostartLegacyValueName);
    finally
      Reg.Free;
    end;
  except
    Result := False;
  end;
end;

function QSSetAutostart(AEnabled: Boolean): Boolean;
var
  Reg: TRegistry;
  ExeName: string;
begin
  Result := False;
  try
    Reg := TRegistry.Create;
    try
      Reg.RootKey := HKEY_CURRENT_USER;
      if not Reg.OpenKey(QSAutostartRegistryKey, True) then
        Exit;

      if AEnabled then
      begin
        ExeName := ExpandFileName(ParamStr(0));
        Reg.WriteString(QSAutostartValueName, '"' + ExeName + '"');
        { Убираем значение прежнего имени, если оно осталось. }
        if Reg.ValueExists(QSAutostartLegacyValueName) then
          Reg.DeleteValue(QSAutostartLegacyValueName);
      end
      else
      begin
        if Reg.ValueExists(QSAutostartValueName) then
          Reg.DeleteValue(QSAutostartValueName);
        if Reg.ValueExists(QSAutostartLegacyValueName) then
          Reg.DeleteValue(QSAutostartLegacyValueName);
      end;

      Result := True;
    finally
      Reg.Free;
    end;
  except
    Result := False;
  end;
end;

{ ------------------------------------------------------------------ }
{ Горячие клавиши                                                    }
{ ------------------------------------------------------------------ }

function QSDefaultHotkey(AKind: TQSHotkeyKind): TQSHotkey;
begin
  Result.Modifiers := MOD_CONTROL or MOD_SHIFT;
  case AKind of
    qshkRegion: Result.VirtualKey := Ord('1');
    qshkWindow: Result.VirtualKey := Ord('2');
    qshkDesktop: Result.VirtualKey := Ord('3');
  else
    Result.VirtualKey := 0;
  end;
end;

function QSIsModifierKey(AKey: Word): Boolean;
begin
  Result := AKey in [
    VK_SHIFT, VK_LSHIFT, VK_RSHIFT,
    VK_CONTROL, VK_LCONTROL, VK_RCONTROL,
    VK_MENU, VK_LMENU, VK_RMENU,
    VK_LWIN, VK_RWIN
  ];
end;

function QSHotkeyIsValid(const AHotkey: TQSHotkey): Boolean;
begin
  Result := (AHotkey.VirtualKey <> 0) and
    not QSIsModifierKey(AHotkey.VirtualKey) and
    ( ((AHotkey.Modifiers and
        (MOD_CONTROL or MOD_ALT or MOD_SHIFT or MOD_WIN)) <> 0) or
      { Print Screen, Scroll Lock и Pause традиционно используются
        одиночными клавишами, поэтому модификатор для них не обязателен. }
      (AHotkey.VirtualKey in [VK_SNAPSHOT, VK_SCROLL, VK_PAUSE]) );
end;

function QSHotkeysEqual(const A, B: TQSHotkey): Boolean;
begin
  Result := (A.Modifiers = B.Modifiers) and (A.VirtualKey = B.VirtualKey);
end;

function QSHotkeyModifiersText(AModifiers: Cardinal): string;
begin
  Result := '';
  if (AModifiers and MOD_CONTROL) <> 0 then
    Result := Result + 'Ctrl+';
  if (AModifiers and MOD_ALT) <> 0 then
    Result := Result + 'Alt+';
  if (AModifiers and MOD_SHIFT) <> 0 then
    Result := Result + 'Shift+';
  if (AModifiers and MOD_WIN) <> 0 then
    Result := Result + 'Win+';
end;

function QSVirtualKeyText(AKey: Word): string;
var
  ScanCode: UINT;
  LParam: LongInt;
  Buf: array[0..63] of Char;
begin
  Result := '';

  if (AKey >= Ord('0')) and (AKey <= Ord('9')) then
  begin
    Result := Char(AKey);
    Exit;
  end;

  if (AKey >= Ord('A')) and (AKey <= Ord('Z')) then
  begin
    Result := Char(AKey);
    Exit;
  end;

  if (AKey >= VK_F1) and (AKey <= VK_F24) then
  begin
    Result := 'F' + IntToStr(AKey - VK_F1 + 1);
    Exit;
  end;

  case AKey of
    VK_BACK: Result := 'Backspace';
    VK_TAB: Result := 'Tab';
    VK_RETURN: Result := 'Enter';
    VK_PAUSE: Result := 'Pause';
    VK_CAPITAL: Result := 'Caps Lock';
    VK_ESCAPE: Result := 'Esc';
    VK_SPACE: Result := 'Space';
    VK_PRIOR: Result := 'Page Up';
    VK_NEXT: Result := 'Page Down';
    VK_END: Result := 'End';
    VK_HOME: Result := 'Home';
    VK_LEFT: Result := 'Left';
    VK_UP: Result := 'Up';
    VK_RIGHT: Result := 'Right';
    VK_DOWN: Result := 'Down';
    VK_INSERT: Result := 'Insert';
    VK_DELETE: Result := 'Delete';
    VK_SNAPSHOT: Result := 'Print Screen';
    VK_NUMLOCK: Result := 'Num Lock';
    VK_SCROLL: Result := 'Scroll Lock';
    VK_OEM_1: Result := ';';
    VK_OEM_PLUS: Result := '+';
    VK_OEM_COMMA: Result := ',';
    VK_OEM_MINUS: Result := '-';
    VK_OEM_PERIOD: Result := '.';
    VK_OEM_2: Result := '/';
    VK_OEM_3: Result := '`';
    VK_OEM_4: Result := '[';
    VK_OEM_5: Result := '\';
    VK_OEM_6: Result := ']';
    VK_OEM_7: Result := '''';
  end;

  if Result <> '' then
    Exit;

  { Для остальных клавиш Windows даёт локализованное название. }
  ScanCode := MapVirtualKey(AKey, MAPVK_VK_TO_VSC);
  if ScanCode <> 0 then
  begin
    LParam := LongInt(ScanCode) shl 16;
    if AKey in [VK_LEFT, VK_UP, VK_RIGHT, VK_DOWN, VK_PRIOR, VK_NEXT,
      VK_END, VK_HOME, VK_INSERT, VK_DELETE] then
      LParam := LParam or (1 shl 24);

    if GetKeyNameText(LParam, PChar(@Buf[0]), Length(Buf)) > 0 then
      Result := string(PChar(@Buf[0]));
  end;

  if Result = '' then
    Result := Format('VK 0x%.2X', [AKey]);
end;

function QSHotkeyText(const AHotkey: TQSHotkey): string;
begin
  if not QSHotkeyIsValid(AHotkey) then
    Exit('не задана');
  Result := QSHotkeyModifiersText(AHotkey.Modifiers) +
    QSVirtualKeyText(AHotkey.VirtualKey);
end;

function QSModifiersFromShift(const AShift: TShiftState): Cardinal;
begin
  Result := 0;
  if ssCtrl in AShift then
    Result := Result or MOD_CONTROL;
  if ssAlt in AShift then
    Result := Result or MOD_ALT;
  if ssShift in AShift then
    Result := Result or MOD_SHIFT;
  if (GetKeyState(VK_LWIN) < 0) or (GetKeyState(VK_RWIN) < 0) then
    Result := Result or MOD_WIN;
end;

function QSHotkeyAvailableNow(const AHotkey: TQSHotkey): Boolean;
const
  QSTestHotkeyId = $BFFF;
begin
  { Проверяем на временной регистрации без окна: если комбинацию уже
    удерживает другая программа, RegisterHotKey вернёт False. }
  if not QSHotkeyIsValid(AHotkey) then
    Exit(True);

  Result := RegisterHotKey(0, QSTestHotkeyId,
    AHotkey.Modifiers, AHotkey.VirtualKey) <> False;
  if Result then
    UnregisterHotKey(0, QSTestHotkeyId);
end;

function QSKnownHotkeyAppTitle(const AExeName: string): string;
begin
  Result := '';

  { Список программ, которые часто занимают глобальные комбинации.
    Точный владелец RegisterHotKey в Windows не запрашивается, поэтому
    это именно подсказка по запущенным процессам. }
  if SameText(AExeName, 'ScreenSketch.exe') or
     SameText(AExeName, 'SnippingTool.exe') or
     SameText(AExeName, 'ScreenClippingHost.exe') then
    Result := 'Ножницы Windows (Snipping Tool)'
  else if SameText(AExeName, 'ShareX.exe') then
    Result := 'ShareX'
  else if SameText(AExeName, 'Snipaste.exe') then
    Result := 'Snipaste'
  else if SameText(AExeName, 'Greenshot.exe') then
    Result := 'Greenshot'
  else if SameText(AExeName, 'Lightshot.exe') then
    Result := 'Lightshot'
  else if SameText(AExeName, 'Screenpresso.exe') then
    Result := 'Screenpresso'
  else if SameText(AExeName, 'PicPick.exe') then
    Result := 'PicPick'
  else if SameText(AExeName, 'FSCapture.exe') then
    Result := 'FastStone Capture'
  else if SameText(AExeName, 'Snagit32.exe') or
          SameText(AExeName, 'Snagit64.exe') or
          SameText(AExeName, 'SnagitEditor.exe') then
    Result := 'Snagit'
  else if SameText(AExeName, 'Bandicam.exe') then
    Result := 'Bandicam'
  else if SameText(AExeName, 'Fraps.exe') then
    Result := 'Fraps'
  else if SameText(AExeName, 'obs32.exe') or
          SameText(AExeName, 'obs64.exe') then
    Result := 'OBS Studio'
  else if SameText(AExeName, 'GameBar.exe') or
          SameText(AExeName, 'GameBarFTServer.exe') then
    Result := 'Xbox Game Bar'
  else if SameText(AExeName, 'OneDrive.exe') then
    Result := 'Microsoft OneDrive'
  else if SameText(AExeName, 'Dropbox.exe') then
    Result := 'Dropbox'
  else if SameText(AExeName, 'GoogleDriveFS.exe') then
    Result := 'Google Drive'
  else if SameText(AExeName, 'Discord.exe') then
    Result := 'Discord'
  else if SameText(AExeName, 'Teams.exe') or
          SameText(AExeName, 'ms-teams.exe') then
    Result := 'Microsoft Teams'
  else if SameText(AExeName, 'Zoom.exe') then
    Result := 'Zoom'
  else if SameText(AExeName, 'Steam.exe') then
    Result := 'Steam'
  else if SameText(AExeName, 'PowerToys.exe') or
          SameText(AExeName, 'PowerToys.PowerLauncher.exe') or
          SameText(AExeName, 'PowerToys.Runner.exe') then
    Result := 'Microsoft PowerToys'
  else if SameText(AExeName, 'AutoHotkey.exe') or
          SameText(AExeName, 'AutoHotkey64.exe') or
          SameText(AExeName, 'AutoHotkeyU64.exe') then
    Result := 'AutoHotkey'
  else if SameText(AExeName, 'Everything.exe') then
    Result := 'Everything'
  else if SameText(AExeName, 'Ditto.exe') then
    Result := 'Ditto'
  else if SameText(AExeName, 'RadeonSoftware.exe') then
    Result := 'AMD Radeon Software'
  else if SameText(AExeName, 'NVIDIA Overlay.exe') or
          SameText(AExeName, 'NVIDIA Share.exe') then
    Result := 'NVIDIA GeForce Experience'
  else if SameText(AExeName, 'Loom.exe') then
    Result := 'Loom'
  else if SameText(AExeName, 'Camtasia.exe') or
          SameText(AExeName, 'CamtasiaRecorder.exe') then
    Result := 'Camtasia'
  else if SameText(AExeName, 'ZoomIt.exe') then
    Result := 'ZoomIt'
  else if SameText(AExeName, 'PrtScr.exe') then
    Result := 'PrtScr';
end;

function QSHotkeyOwnerHint(const AHotkey: TQSHotkey): string;
var
  Snap: THandle;
  PE: TProcessEntry32;
  Names: TStringList;
  AppTitle: string;
  SelfPid: Cardinal;
  I: Integer;
begin
  Result := '';
  if not QSHotkeyIsValid(AHotkey) then
    Exit;

  Names := TStringList.Create;
  try
    Names.CaseSensitive := False;
    Names.Sorted := True;
    Names.Duplicates := dupIgnore;

    SelfPid := GetCurrentProcessId;
    Snap := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if Snap <> INVALID_HANDLE_VALUE then
    try
      PE.dwSize := SizeOf(PE);
      if Process32First(Snap, PE) then
        repeat
          if PE.th32ProcessID <> SelfPid then
          begin
            { szExeFile - массив WChar с завершающим нулём; приводим к PChar,
              чтобы не зависеть от неявного преобразования массива в string. }
            AppTitle := QSKnownHotkeyAppTitle(string(PChar(@PE.szExeFile)));
            if AppTitle <> '' then
              Names.Add(AppTitle);
          end;
        until not Process32Next(Snap, PE);
    finally
      CloseHandle(Snap);
    end;

    if Names.Count = 0 then
      Exit;

    Result := 'Вероятно, комбинацию использует: ';
    for I := 0 to Names.Count - 1 do
    begin
      if I > 0 then
        Result := Result + ', ';
      Result := Result + Names[I];
      if I >= 3 then
      begin
        if Names.Count > 4 then
          Result := Result + ' и др.';
        Break;
      end;
    end;
  finally
    Names.Free;
  end;
end;

procedure QSNormalizeHotkeys(var AHotkeys: TQSHotkeys);
var
  K, P: TQSHotkeyKind;
  Duplicate: Boolean;
begin
  for K := Low(TQSHotkeyKind) to High(TQSHotkeyKind) do
    if not QSHotkeyIsValid(AHotkeys[K]) then
      AHotkeys[K] := QSDefaultHotkey(K);

  { Дубликаты в INI могли появиться после ручного редактирования. }
  for K := qshkWindow to qshkDesktop do
  begin
    Duplicate := False;
    for P := Low(TQSHotkeyKind) to Pred(K) do
      if QSHotkeysEqual(AHotkeys[K], AHotkeys[P]) then
      begin
        Duplicate := True;
        Break;
      end;

    if Duplicate then
    begin
      AHotkeys[K] := QSDefaultHotkey(K);

      { Если и значение по умолчанию занято, комбинацию отключаем. }
      for P := Low(TQSHotkeyKind) to Pred(K) do
        if QSHotkeysEqual(AHotkeys[K], AHotkeys[P]) then
        begin
          AHotkeys[K].Modifiers := 0;
          AHotkeys[K].VirtualKey := 0;
          Break;
        end;
    end;
  end;
end;

{ ------------------------------------------------------------------ }
{ TQSAppSettings                                                     }
{ ------------------------------------------------------------------ }

constructor TQSAppSettings.Create;
begin
  inherited Create;
  SetDefaults;
end;

procedure TQSAppSettings.SetDefaults;
var
  K: TQSHotkeyKind;
begin
  SaveFolder := QSDefaultSaveFolder;
  LastSaveDir := '';
  SaveFormat := qsifPng;
  JpegQuality := 92;
  OpenEditorAfterCapture := True;
  CopyAfterCapture := False;
  MinimizeToTray := True;
  ShowNotifications := True;
  LastMonitorIndex := 0;
  StartMinimized := False;
  Autostart := False;

  for K := Low(TQSHotkeyKind) to High(TQSHotkeyKind) do
    Hotkeys[K] := QSDefaultHotkey(K);

  { Параметры редактора: значения по умолчанию совпадают с QSDefault*
    в u_qs_editor.pas. }
  EditorPenColor := $FFFF3B30; { красный }
  EditorFillColor := $FF007AFF; { синий }
  EditorMarkerColor := $FFFFD600; { жёлтый маркер }
  EditorPenWidth := 3;
  EditorFillOpacity := 35;
  EditorTextSize := 24;
  EditorTextFill := False;
  EditorTextBorder := False;
  EditorTextBorderWidth := 3;
  EditorTextPadding := 8;
  EditorArrowHead := False;
  EditorMarkerOpacity := 35;
  EditorMarkerPenWidth := 24;
  EditorMarkerRoundCap := False;
  EditorNumFillColor := $FFFF3B30; { красный круг }
  EditorNumTextColor := $FFFFFFFF; { белые цифры }
  EditorNumSize := 36;
  EditorNumSquare := False;
end;

procedure TQSAppSettings.Assign(Source: TPersistent);
var
  S: TQSAppSettings;
begin
  if Source is TQSAppSettings then
  begin
    S := TQSAppSettings(Source);
    SaveFolder := S.SaveFolder;
    LastSaveDir := S.LastSaveDir;
    SaveFormat := S.SaveFormat;
    JpegQuality := S.JpegQuality;
    OpenEditorAfterCapture := S.OpenEditorAfterCapture;
    CopyAfterCapture := S.CopyAfterCapture;
    MinimizeToTray := S.MinimizeToTray;
    ShowNotifications := S.ShowNotifications;
    LastMonitorIndex := S.LastMonitorIndex;
    StartMinimized := S.StartMinimized;
    Autostart := S.Autostart;
    Hotkeys := S.Hotkeys;

    EditorPenColor := S.EditorPenColor;
    EditorFillColor := S.EditorFillColor;
    EditorMarkerColor := S.EditorMarkerColor;
    EditorPenWidth := S.EditorPenWidth;
    EditorFillOpacity := S.EditorFillOpacity;
    EditorTextSize := S.EditorTextSize;
    EditorTextFill := S.EditorTextFill;
    EditorTextBorder := S.EditorTextBorder;
    EditorTextBorderWidth := S.EditorTextBorderWidth;
    EditorTextPadding := S.EditorTextPadding;
    EditorArrowHead := S.EditorArrowHead;
    EditorMarkerOpacity := S.EditorMarkerOpacity;
    EditorMarkerPenWidth := S.EditorMarkerPenWidth;
    EditorMarkerRoundCap := S.EditorMarkerRoundCap;
    EditorNumFillColor := S.EditorNumFillColor;
    EditorNumTextColor := S.EditorNumTextColor;
    EditorNumSize := S.EditorNumSize;
    EditorNumSquare := S.EditorNumSquare;
  end
  else
    inherited Assign(Source);
end;

procedure TQSAppSettings.LoadFromIni(AIni: TCustomIniFile;
  const ASection, ALegacySection: string);
var
  K: TQSHotkeyKind;

  function ReadText(const AKey, ADefault: string): string;
  begin
    Result := AIni.ReadString(ASection, AKey, '');
    if Result = '' then
      Result := AIni.ReadString(ALegacySection, AKey, '');
    if Result = '' then
      Result := AIni.ReadString(QSLegacyIniSection2, AKey, '');
    if Result = '' then
      Result := ADefault;
  end;

  function ReadInt(const AKey: string; ADefault: Integer): Integer;
  begin
    Result := StrToIntDef(ReadText(AKey, IntToStr(ADefault)), ADefault);
  end;

  function ReadBoolValue(const AKey: string; ADefault: Boolean): Boolean;
  var
    S: string;
  begin
    S := ReadText(AKey, '');
    if S = '' then
      Exit(ADefault);
    if SameText(S, 'true') or (S = '1') or SameText(S, 'yes') then
      Exit(True);
    if SameText(S, 'false') or (S = '0') or SameText(S, 'no') then
      Exit(False);
    Result := ADefault;
  end;

  function ReadHotkey(AKind: TQSHotkeyKind): TQSHotkey;
  var
    KeyName, ModName: string;
    Default: TQSHotkey;
  begin
    Default := QSDefaultHotkey(AKind);
    case AKind of
      qshkRegion:
        begin
          ModName := 'HotkeyRegionModifiers';
          KeyName := 'HotkeyRegionKey';
        end;
      qshkWindow:
        begin
          ModName := 'HotkeyWindowModifiers';
          KeyName := 'HotkeyWindowKey';
        end;
    else
      ModName := 'HotkeyDesktopModifiers';
      KeyName := 'HotkeyDesktopKey';
    end;

    Result.Modifiers := Cardinal(StrToInt64Def(
      ReadText(ModName, IntToStr(Int64(Default.Modifiers))),
      Int64(Default.Modifiers)));
    Result.VirtualKey := Word(StrToIntDef(
      ReadText(KeyName, IntToStr(Default.VirtualKey)), Default.VirtualKey));
    if not QSHotkeyIsValid(Result) then
      Result := Default;
  end;

  { Параметры редактора лежат в отдельной секции [Editor], поэтому
    читаются напрямую, без переноса из старых секций. }

  function ReadEditorText(const AKey, ADefault: string): string;
  begin
    Result := AIni.ReadString(QSEditorIniSection, AKey, '');
    if Result = '' then
      Result := ADefault;
  end;

  function ReadEditorInt(const AKey: string; ADefault: Integer): Integer;
  begin
    Result := StrToIntDef(ReadEditorText(AKey, IntToStr(ADefault)), ADefault);
  end;

  function ReadEditorBool(const AKey: string; ADefault: Boolean): Boolean;
  var
    S: string;
  begin
    S := ReadEditorText(AKey, '');
    if S = '' then
      Exit(ADefault);
    if SameText(S, 'true') or (S = '1') or SameText(S, 'yes') then
      Exit(True);
    if SameText(S, 'false') or (S = '0') or SameText(S, 'no') then
      Exit(False);
    Result := ADefault;
  end;

  function ReadEditorColor(const AKey: string;
    ADefault: TAlphaColor): TAlphaColor;
  var
    S: string;
    I, V: Integer;
  begin
    Result := ADefault;
    S := Trim(ReadEditorText(AKey, ''));
    if Length(S) <> 8 then
      Exit;
    V := 0;
    for I := 1 to 8 do
    begin
      case S[I] of
        '0'..'9': V := V * 16 + (Ord(S[I]) - Ord('0'));
        'a'..'f': V := V * 16 + (Ord(S[I]) - Ord('a') + 10);
        'A'..'F': V := V * 16 + (Ord(S[I]) - Ord('A') + 10);
      else
        Exit; { не hex-строка - используем значение по умолчанию }
      end;
    end;
    Result := TAlphaColor(V);
  end;

begin
  SaveFolder := ReadText('SaveFolder', SaveFolder);
  LastSaveDir := ReadText('LastSaveDir', LastSaveDir);
  SaveFormat := TQSImageFormat(EnsureRange(
    ReadInt('Format', Ord(SaveFormat)), 0, 1));
  JpegQuality := EnsureRange(ReadInt('JpegQuality', JpegQuality), 1, 100);
  OpenEditorAfterCapture := ReadBoolValue('OpenEditor', OpenEditorAfterCapture);
  CopyAfterCapture := ReadBoolValue('CopyAfterCapture', CopyAfterCapture);
  MinimizeToTray := ReadBoolValue('MinimizeToTray', MinimizeToTray);
  ShowNotifications := ReadBoolValue('Notifications', ShowNotifications);
  LastMonitorIndex := ReadInt('MonitorIndex', LastMonitorIndex);
  StartMinimized := ReadBoolValue('StartMinimized', StartMinimized);
  Autostart := ReadBoolValue('Autostart', Autostart);

  for K := Low(TQSHotkeyKind) to High(TQSHotkeyKind) do
    Hotkeys[K] := ReadHotkey(K);

  EditorPenColor := ReadEditorColor('PenColor', EditorPenColor);
  EditorFillColor := ReadEditorColor('FillColor', EditorFillColor);
  EditorMarkerColor := ReadEditorColor('MarkerColor', EditorMarkerColor);
  EditorPenWidth := EnsureRange(
    ReadEditorInt('PenWidth', EditorPenWidth), 1, 20);
  EditorFillOpacity := EnsureRange(
    ReadEditorInt('FillOpacity', EditorFillOpacity), 0, 100);
  EditorTextSize := EnsureRange(
    ReadEditorInt('TextSize', EditorTextSize), 10, 72);
  EditorTextFill := ReadEditorBool('TextFill', EditorTextFill);
  EditorTextBorder := ReadEditorBool('TextBorder', EditorTextBorder);
  EditorTextBorderWidth := EnsureRange(
    ReadEditorInt('TextBorderWidth', EditorTextBorderWidth), 1, 20);
  EditorTextPadding := EnsureRange(
    ReadEditorInt('TextPadding', EditorTextPadding), 0, 48);
  EditorArrowHead := ReadEditorBool('ArrowHead', EditorArrowHead);
  EditorMarkerOpacity := EnsureRange(
    ReadEditorInt('MarkerOpacity', EditorMarkerOpacity), 0, 100);
  EditorMarkerPenWidth := EnsureRange(
    ReadEditorInt('MarkerPenWidth', EditorMarkerPenWidth), 4, 80);
  EditorMarkerRoundCap := ReadEditorBool('MarkerRoundCap', EditorMarkerRoundCap);
  EditorNumFillColor := ReadEditorColor('NumFillColor', EditorNumFillColor);
  EditorNumTextColor := ReadEditorColor('NumTextColor', EditorNumTextColor);
  EditorNumSize := EnsureRange(
    ReadEditorInt('NumSize', EditorNumSize), 12, 100);
  EditorNumSquare := ReadEditorBool('NumSquare', EditorNumSquare);

  QSNormalizeHotkeys(Hotkeys);
end;

procedure TQSAppSettings.SaveToIni(AIni: TCustomIniFile; const ASection: string);
var
  K: TQSHotkeyKind;
  ModName, KeyName: string;
begin
  AIni.WriteString(ASection, 'SaveFolder', SaveFolder);
  if LastSaveDir <> '' then
    AIni.WriteString(ASection, 'LastSaveDir', LastSaveDir);
  AIni.WriteInteger(ASection, 'Format', Ord(SaveFormat));
  AIni.WriteInteger(ASection, 'JpegQuality', JpegQuality);
  AIni.WriteBool(ASection, 'OpenEditor', OpenEditorAfterCapture);
  AIni.WriteBool(ASection, 'CopyAfterCapture', CopyAfterCapture);
  AIni.WriteBool(ASection, 'MinimizeToTray', MinimizeToTray);
  AIni.WriteBool(ASection, 'Notifications', ShowNotifications);
  AIni.WriteInteger(ASection, 'MonitorIndex', LastMonitorIndex);
  AIni.WriteBool(ASection, 'StartMinimized', StartMinimized);
  AIni.WriteBool(ASection, 'Autostart', Autostart);

  for K := Low(TQSHotkeyKind) to High(TQSHotkeyKind) do
  begin
    case K of
      qshkRegion:
        begin
          ModName := 'HotkeyRegionModifiers';
          KeyName := 'HotkeyRegionKey';
        end;
      qshkWindow:
        begin
          ModName := 'HotkeyWindowModifiers';
          KeyName := 'HotkeyWindowKey';
        end;
    else
      ModName := 'HotkeyDesktopModifiers';
      KeyName := 'HotkeyDesktopKey';
    end;
    AIni.WriteInteger(ASection, ModName, Integer(Hotkeys[K].Modifiers));
    AIni.WriteInteger(ASection, KeyName, Hotkeys[K].VirtualKey);
  end;

  { Параметры редактора снимков - отдельная секция [Editor]. }
  AIni.WriteString(QSEditorIniSection, 'PenColor',
    IntToHex(EditorPenColor, 8));
  AIni.WriteString(QSEditorIniSection, 'FillColor',
    IntToHex(EditorFillColor, 8));
  AIni.WriteString(QSEditorIniSection, 'MarkerColor',
    IntToHex(EditorMarkerColor, 8));
  AIni.WriteInteger(QSEditorIniSection, 'PenWidth', EditorPenWidth);
  AIni.WriteInteger(QSEditorIniSection, 'FillOpacity', EditorFillOpacity);
  AIni.WriteInteger(QSEditorIniSection, 'TextSize', EditorTextSize);
  AIni.WriteBool(QSEditorIniSection, 'TextFill', EditorTextFill);
  AIni.WriteBool(QSEditorIniSection, 'TextBorder', EditorTextBorder);
  AIni.WriteInteger(QSEditorIniSection, 'TextBorderWidth', EditorTextBorderWidth);
  AIni.WriteInteger(QSEditorIniSection, 'TextPadding', EditorTextPadding);
  AIni.WriteBool(QSEditorIniSection, 'ArrowHead', EditorArrowHead);
  AIni.WriteInteger(QSEditorIniSection, 'MarkerOpacity', EditorMarkerOpacity);
  AIni.WriteInteger(QSEditorIniSection, 'MarkerPenWidth', EditorMarkerPenWidth);
  AIni.WriteBool(QSEditorIniSection, 'MarkerRoundCap', EditorMarkerRoundCap);
  AIni.WriteString(QSEditorIniSection, 'NumFillColor',
    IntToHex(EditorNumFillColor, 8));
  AIni.WriteString(QSEditorIniSection, 'NumTextColor',
    IntToHex(EditorNumTextColor, 8));
  AIni.WriteInteger(QSEditorIniSection, 'NumSize', EditorNumSize);
  AIni.WriteBool(QSEditorIniSection, 'NumSquare', EditorNumSquare);
end;

procedure TQSAppSettings.Load;
var
  Ini: TIniFile;
  FileName: string;
begin
  SetDefaults;
  QSEnsureSettingsMigrated;

  FileName := QSSettingsFileName;
  if FileExists(FileName) then
  try
    Ini := TIniFile.Create(FileName);
    try
      LoadFromIni(Ini, QSAppIniSection, QSLegacyIniSection);
    finally
      Ini.Free;
    end;
  except
    SetDefaults;
  end;

  if Trim(SaveFolder) = '' then
    SaveFolder := QSDefaultSaveFolder;
  if Trim(LastSaveDir) = '' then
    LastSaveDir := SaveFolder;
  if LastMonitorIndex < 0 then
    LastMonitorIndex := 0;

  { Реестр - источник истины для автозапуска. }
  Autostart := QSAutostartEnabled;
end;

procedure TQSAppSettings.Save;
var
  Ini: TIniFile;
  FileName, Dir: string;
begin
  FileName := QSSettingsFileName;
  Dir := ExtractFileDir(FileName);
  if Dir <> '' then
    ForceDirectories(Dir);

  try
    Ini := TIniFile.Create(FileName);
    try
      SaveToIni(Ini, QSAppIniSection);
    finally
      Ini.Free;
    end;
  except
    { Настройки не критичны: при ошибке записи просто продолжаем работу. }
  end;
end;

{ ------------------------------------------------------------------ }
{ TQSSettingsForm - создание элементов                               }
{ ------------------------------------------------------------------ }

function TQSSettingsForm.NewLabel(AParent: TControl; const AText: string;
  AX, AY, AWidth, AHeight: Single; ABold: Boolean;
  AWordWrap: Boolean): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(AX, AY, AWidth, AHeight);
  Result.AutoSize := False;
  Result.TextAlign := TTextAlign.Leading;
  Result.VertTextAlign := TTextAlign.Center;
  Result.WordWrap := AWordWrap;
  Result.HitTest := False;
  Result.Text := AText;
  Result.StyledSettings := Result.StyledSettings -
    [TStyledSetting.Size, TStyledSetting.Style];
  if ABold then
    Result.Font.Style := [TFontStyle.fsBold];
end;

function TQSSettingsForm.NewButton(AParent: TControl; const AText: string;
  AX, AY, AWidth, AHeight: Single): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(AX, AY, AWidth, AHeight);
  Result.Text := AText;
end;

function TQSSettingsForm.NewCheckBox(AParent: TControl; const AText: string;
  AX, AY, AWidth: Single): TCheckBox;
begin
  Result := TCheckBox.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(AX, AY, AWidth, 24);
  Result.Text := AText;
end;

function TQSSettingsForm.NewGroupBox(AParent: TControl; const AText: string;
  AX, AY, AWidth, AHeight: Single): TGroupBox;
begin
  Result := TGroupBox.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(AX, AY, AWidth, AHeight);
  Result.Text := AText;
end;

function TQSSettingsForm.AddPage(const ACaption: string): TTabItem;
begin
  Result := FTabs.Add;
  Result.Text := ACaption;
  FNav.Items.Add(ACaption);
end;

procedure TQSSettingsForm.BuildUI;
var
  Page: TTabItem;
begin
  Caption := 'Настройки';
  BorderStyle := TFmxFormBorderStyle.Sizeable;
  Constraints.MinWidth := 900;
  Constraints.MinHeight := 620;
  Width := 960;
  Height := 660;
  Position := TFormPosition.ScreenCenter;

  OnResize := FormResize;
  OnDeactivate := FormDeactivate;
  OnDestroy := FormDestroy;

  { ---------------- Заголовок ---------------- }
  FHeaderPanel := TPanel.Create(Self);
  FHeaderPanel.Parent := Self;
  FHeaderPanel.Align := TAlignLayout.Top;
  FHeaderPanel.Height := 64;

  with NewLabel(FHeaderPanel, 'Настройки', 16, 8, 300, 30, True) do
    Font.Size := 18;
  NewLabel(FHeaderPanel, 'Параметры снимков, сохранения, горячих клавиш и запуска',
    18, 38, 500, 20);

  { ---------------- Нижняя панель ---------------- }
  FBottomPanel := TPanel.Create(Self);
  FBottomPanel.Parent := Self;
  FBottomPanel.Align := TAlignLayout.Bottom;
  FBottomPanel.Height := 64;

  FBtnSave := NewButton(FBottomPanel, 'Сохранить', 0, 14, 120, 34);
  FBtnSave.OnClick := btnSaveClick;

  FBtnCancel := NewButton(FBottomPanel, 'Отмена', 0, 14, 110, 34);
  FBtnCancel.OnClick := btnCancelClick;

  { ---------------- Навигация ---------------- }
  FNav := TListBox.Create(Self);
  FNav.Parent := Self;
  FNav.Align := TAlignLayout.Left;
  FNav.Width := 200;
  FNav.ItemHeight := 42;
  FNav.Margins.Left := 12;
  FNav.Margins.Top := 8;
  FNav.Margins.Bottom := 12;
  FNav.OnChange := NavChange;

  { ---------------- Страницы ---------------- }
  FTabs := TTabControl.Create(Self);
  FTabs.Parent := Self;
  FTabs.Align := TAlignLayout.Client;
  FTabs.TabPosition := TTabPosition.None;
  FTabs.Margins.Left := 8;
  FTabs.Margins.Top := 8;
  FTabs.Margins.Right := 12;
  FTabs.Margins.Bottom := 12;

  Page := AddPage('Снимки');
  BuildCapturesPage(Page);
  Page := AddPage('Сохранение');
  BuildSavePage(Page);
  Page := AddPage('Горячие клавиши');
  BuildHotkeysPage(Page);
  Page := AddPage('Поведение');
  BuildBehaviorPage(Page);
  Page := AddPage('О программе');
  BuildAboutPage(Page);

  FNav.ItemIndex := 0;
  if FTabs.TabCount > 0 then
    FTabs.ActiveTab := FTabs.Tabs[0];

  FormResize(Self);
end;

procedure TQSSettingsForm.BuildCapturesPage(APage: TTabItem);
var
  G: TGroupBox;
begin
  G := NewGroupBox(APage, 'После снимка', 16, 16, 630, 150);

  FChkEditor := NewCheckBox(G, 'Открывать редактор после снимка', 16, 32, 580);
  FChkCopy := NewCheckBox(G, 'Копировать снимок в буфер обмена', 16, 64, 580);

  NewLabel(G,
    'Редактор позволяет разметить снимок, а копирование в буфер удобно ' +
    'для быстрой вставки в другие программы.',
    16, 100, 590, 38, False, True);
end;

procedure TQSSettingsForm.BuildSavePage(APage: TTabItem);
var
  G: TGroupBox;
begin
  G := NewGroupBox(APage, 'Папка и формат', 16, 16, 630, 250);

  NewLabel(G, 'Папка для сохранения', 16, 28, 300, 18);

  FEdFolder := TEdit.Create(Self);
  FEdFolder.Parent := G;
  FEdFolder.SetBounds(16, 50, 380, 30);

  FBtnBrowse := NewButton(G, 'Обзор...', 404, 50, 100, 30);
  FBtnBrowse.OnClick := btnBrowseClick;

  NewLabel(G, 'Формат файла', 16, 94, 300, 18);

  FCmbFormat := TComboBox.Create(Self);
  FCmbFormat.Parent := G;
  FCmbFormat.SetBounds(16, 116, 260, 30);
  FCmbFormat.Items.Add('PNG (*.png)');
  FCmbFormat.Items.Add('JPEG (*.jpg; *.jpeg)');
  FCmbFormat.OnChange := cmbFormatChange;

  NewLabel(G, 'Качество JPEG (1-100)', 16, 160, 300, 18);

  FQualityTrack := TTrackBar.Create(Self);
  FQualityTrack.Parent := G;
  FQualityTrack.SetBounds(16, 182, 330, 30);
  FQualityTrack.Orientation := TOrientation.Horizontal;
  FQualityTrack.Min := 1;
  FQualityTrack.Max := 100;
  FQualityTrack.Frequency := 1;
  FQualityTrack.OnChange := tbQualityChange;

  FQualityValue := NewLabel(G, '92', 354, 182, 60, 30);

  G := NewGroupBox(APage, 'Имена файлов', 16, 282, 630, 100);
  NewLabel(G,
    'Снимки получают имя QS Click_ГГГГ-ММ-ДД_ЧЧ-ММ-СС.png (или .jpg). ' +
    'При совпадении имени добавляется номер.',
    16, 28, 590, 44, False, True);
end;

procedure TQSSettingsForm.BuildHotkeysPage(APage: TTabItem);
var
  G: TGroupBox;
  K: TQSHotkeyKind;
  Y: Single;
  B: TButton;
  Caption: string;
begin
  G := NewGroupBox(APage, 'Глобальные комбинации', 16, 16, 630, 266);

  for K := Low(TQSHotkeyKind) to High(TQSHotkeyKind) do
  begin
    case K of
      qshkRegion: Caption := 'Снимок области';
      qshkWindow: Caption := 'Активное окно';
    else
      Caption := 'Весь рабочий стол';
    end;

    Y := 32 + Ord(K) * 46;
    NewLabel(G, Caption, 16, Y + 6, 190, 22);

    FHotkeyEdits[K] := TEdit.Create(Self);
    FHotkeyEdits[K].Parent := G;
    FHotkeyEdits[K].SetBounds(212, Y, 220, 30);
    FHotkeyEdits[K].ReadOnly := True;
    FHotkeyEdits[K].OnKeyDown := HotkeyEditKeyDown;
    FHotkeyEdits[K].OnExit := HotkeyEditExit;

    B := NewButton(G, 'Задать', 444, Y, 100, 30);
    B.Tag := Ord(K);
    B.OnClick := btnHotkeyClick;
  end;

  FHotkeyStatus := NewLabel(G, '', 16, 170, 590, 36);
  FHotkeyStatus.WordWrap := True;
  FHotkeyStatus.StyledSettings := FHotkeyStatus.StyledSettings -
    [TStyledSetting.FontColor];
  FHotkeyStatus.FontColor := $FF6B6B6B;

  B := NewButton(G, 'Сбросить всё', 212, 216, 150, 30);
  B.OnClick := btnResetHotkeysClick;

  G := NewGroupBox(APage, 'Правила', 16, 298, 630, 144);
  NewLabel(G,
    'Комбинация должна содержать хотя бы один модификатор: Ctrl, Alt, Shift ' +
    'или Win. Исключение - Print Screen, Scroll Lock и Pause: их можно ' +
    'назначить и без модификатора. Во время назначения глобальные клавиши ' +
    'временно отключаются. Esc отменяет захват.',
    16, 28, 590, 92, False, True);
end;

procedure TQSSettingsForm.BuildBehaviorPage(APage: TTabItem);
var
  G: TGroupBox;
begin
  G := NewGroupBox(APage, 'Главное окно', 16, 16, 630, 176);

  FChkMinimizeToTray := NewCheckBox(G,
    'Скрывать в область уведомлений при закрытии', 16, 32, 580);
  FChkStartMinimized := NewCheckBox(G,
    'Запускать программу свёрнутой в область уведомлений', 16, 64, 580);

  NewLabel(G,
    'Если закрытие в трей включено, кнопка закрытия окна убирает программу ' +
    'с панели задач. Двойной щелчок по значку возвращает окно.',
    16, 100, 590, 48, False, True);

  G := NewGroupBox(APage, 'Уведомления', 16, 208, 630, 100);

  FChkNotifications := NewCheckBox(G,
    'Показывать уведомления о готовых снимках', 16, 32, 580);

  G := NewGroupBox(APage, 'Запуск с Windows', 16, 324, 630, 116);

  FChkAutostart := NewCheckBox(G,
    'Запускать QS Click при входе в Windows', 16, 32, 580);

  NewLabel(G,
    'Автозапуск прописывается только для текущего пользователя в ' +
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Run.',
    16, 64, 590, 38, False, True);
end;

procedure TQSSettingsForm.BuildAboutPage(APage: TTabItem);
var
  Host: TPanel;
  Footer: TLabel;
  {$IF Defined(MSWINDOWS) and not Defined(WIN64) and not Defined(QS_NO_MARKDOWN4D)}
  Viewer: TMarkdownViewer;
  {$ELSE}
  Memo: TMemo;
  AboutText: string;
  {$ENDIF}
begin
  QSEnsureAboutFile;

  Footer := NewLabel(APage,
    QSAppCaption + ' ' + QSAppVersion + '  ·  Автор: ' + QSAppAuthor +
    '  ·  ' + QSAppWebsite,
    12, 0, 700, 26);
  Footer.Align := TAlignLayout.Bottom;
  Footer.Margins.Left := 12;
  Footer.Margins.Right := 12;
  Footer.Margins.Bottom := 4;
  Footer.TextAlign := TTextAlign.Center;
  { Подпись сделана ссылкой на сайт: включим HitTest, иначе TLabel
    не получает щелчки. }
  Footer.HitTest := True;
  Footer.Cursor := crHandPoint;
  Footer.OnClick := AboutFooterClick;

  Host := TPanel.Create(Self);
  Host.Parent := APage;
  Host.Align := TAlignLayout.Client;
  Host.Margins.Left := 12;
  Host.Margins.Top := 8;
  Host.Margins.Right := 12;
  Host.Margins.Bottom := 8;

  {$IF Defined(MSWINDOWS) and not Defined(WIN64) and not Defined(QS_NO_MARKDOWN4D)}
  Viewer := TMarkdownViewer.Create(Self);
  Viewer.Parent := Host;
  Viewer.Align := TAlignLayout.Client;
  { Ссылки в about.md открываются в браузере. У TMarkdownViewer для этого
    есть штатное событие OnLinkClick(Sender, Url). }
  Viewer.OnLinkClick := MarkdownLinkClick;
  try
    Viewer.LoadFromFile(QSAboutFileName);
  except
    try
      Viewer.Text := System.IOUtils.TFile.ReadAllText(QSAboutFileName,
        TEncoding.UTF8);
    except
      Viewer.Text := '# QS Click' + sLineBreak + sLineBreak +
        'Не удалось загрузить описание программы.';
    end;
  end;
  {$ELSE}
  Memo := TMemo.Create(Self);
  Memo.Parent := Host;
  Memo.Align := TAlignLayout.Client;
  Memo.ReadOnly := True;
  Memo.WordWrap := True;
  try
    AboutText := System.IOUtils.TFile.ReadAllText(QSAboutFileName,
      TEncoding.UTF8);
  except
    AboutText := '# QS Click' + sLineBreak + sLineBreak +
      'Не удалось загрузить описание программы.';
  end;
  Memo.Text := AboutText;
  {$ENDIF}
end;

procedure TQSSettingsForm.OpenExternalUrl(const AUrl: string);
var
  Url: string;
begin
  Url := Trim(AUrl);
  if Url = '' then
    Exit;

  { Внутренние якоря Markdown оставляем просмотрщику. }
  if Url[1] = '#' then
    Exit;

  ShellExecute(0, 'open', PChar(Url), nil, nil, SW_SHOWNORMAL);
end;

procedure TQSSettingsForm.MarkdownLinkClick(const Sender: TObject;
  const AUrl: string);
begin
  OpenExternalUrl(AUrl);
end;

procedure TQSSettingsForm.AboutFooterClick(Sender: TObject);
begin
  OpenExternalUrl(QSAppUrl);
end;

procedure TQSSettingsForm.LoadValues;
var
  K: TQSHotkeyKind;
begin
  if FEditing = nil then
    Exit;

  if FEdFolder <> nil then
    FEdFolder.Text := FEditing.SaveFolder;
  if FCmbFormat <> nil then
    FCmbFormat.ItemIndex := Ord(FEditing.SaveFormat);
  if FQualityTrack <> nil then
    FQualityTrack.Value := FEditing.JpegQuality;
  if FQualityValue <> nil then
    FQualityValue.Text := IntToStr(FEditing.JpegQuality);
  UpdateQualityState;

  if FChkEditor <> nil then
    FChkEditor.IsChecked := FEditing.OpenEditorAfterCapture;
  if FChkCopy <> nil then
    FChkCopy.IsChecked := FEditing.CopyAfterCapture;
  if FChkMinimizeToTray <> nil then
    FChkMinimizeToTray.IsChecked := FEditing.MinimizeToTray;
  if FChkStartMinimized <> nil then
    FChkStartMinimized.IsChecked := FEditing.StartMinimized;
  if FChkAutostart <> nil then
    FChkAutostart.IsChecked := FEditing.Autostart;
  if FChkNotifications <> nil then
    FChkNotifications.IsChecked := FEditing.ShowNotifications;

  for K := Low(TQSHotkeyKind) to High(TQSHotkeyKind) do
    if FHotkeyEdits[K] <> nil then
      FHotkeyEdits[K].Text := QSHotkeyText(FEditing.Hotkeys[K]);

  SetHotkeyStatus('Нажмите «Задать», чтобы назначить новую комбинацию.', False);
end;

procedure TQSSettingsForm.Initialize(const ASettings: TQSAppSettings);
begin
  FreeAndNil(FEditing);
  FEditing := TQSAppSettings.Create;
  FEditing.Assign(ASettings);
  BuildUI;
  LoadValues;
end;

procedure TQSSettingsForm.UpdateQualityState;
begin
  if (FQualityTrack = nil) or (FCmbFormat = nil) then
    Exit;
  FQualityTrack.Enabled := FCmbFormat.ItemIndex = Ord(qsifJpeg);
  if FQualityValue <> nil then
    FQualityValue.Enabled := FQualityTrack.Enabled;
end;

procedure TQSSettingsForm.UpdateHotkeyEdits;
var
  K: TQSHotkeyKind;
begin
  if FEditing = nil then
    Exit;
  for K := Low(TQSHotkeyKind) to High(TQSHotkeyKind) do
    if FHotkeyEdits[K] <> nil then
      FHotkeyEdits[K].Text := QSHotkeyText(FEditing.Hotkeys[K]);
end;

procedure TQSSettingsForm.SetHotkeyStatus(const AText: string;
  AError: Boolean);
begin
  if FHotkeyStatus = nil then
    Exit;
  FHotkeyStatus.Text := AText;
  if AError then
    FHotkeyStatus.FontColor := $FFD9534F
  else
    FHotkeyStatus.FontColor := $FF6B6B6B;
end;

procedure TQSSettingsForm.SelectPage(AIndex: Integer);
begin
  if (FNav <> nil) and (AIndex >= 0) and (AIndex < FNav.Items.Count) then
    FNav.ItemIndex := AIndex;
end;

procedure TQSSettingsForm.BeginHotkeyCapture(AKind: TQSHotkeyKind);
begin
  if FEditing = nil then
    Exit;

  if FCapturing then
    EndHotkeyCapture;

  FCapturing := True;
  FCaptureKind := AKind;
  if FHotkeyEdits[AKind] <> nil then
  begin
    { ReadOnly-поле в FMX может не передавать нажатия в OnKeyDown,
      поэтому на время захвата поле становится обычным. Ввод символов
      всё равно блокируется в HotkeyEditKeyDown. }
    FHotkeyEdits[AKind].ReadOnly := False;
    FHotkeyEdits[AKind].Text := 'Нажмите комбинацию...';
    FHotkeyEdits[AKind].SetFocus;
  end;
  SetHotkeyStatus('Ожидание комбинации. Esc - отмена.', False);
end;

procedure TQSSettingsForm.EndHotkeyCapture;
var
  K: TQSHotkeyKind;
begin
  if not FCapturing then
    Exit;
  FCapturing := False;
  for K := Low(TQSHotkeyKind) to High(TQSHotkeyKind) do
    if FHotkeyEdits[K] <> nil then
      FHotkeyEdits[K].ReadOnly := True;
  UpdateHotkeyEdits;
end;

procedure TQSSettingsForm.HotkeyEditExit(Sender: TObject);
begin
  if not FCapturing then
    Exit;
  EndHotkeyCapture;
  SetHotkeyStatus('Нажмите «Задать», чтобы назначить новую комбинацию.', False);
end;

procedure TQSSettingsForm.HotkeyEditKeyDown(Sender: TObject; var Key: Word;
  var KeyChar: WideChar; Shift: TShiftState);
var
  H: TQSHotkey;
  Other: TQSHotkeyKind;
  Mods: Cardinal;
  OwnerHint: string;
begin
  if not FCapturing then
    Exit;
  if Key = 0 then
    Exit;

  if Key = VK_ESCAPE then
  begin
    EndHotkeyCapture;
    SetHotkeyStatus('Назначение отменено.', False);
    Key := 0;
    KeyChar := #0;
    Exit;
  end;

  Mods := QSModifiersFromShift(Shift);

  if QSIsModifierKey(Key) then
  begin
    if FHotkeyEdits[FCaptureKind] <> nil then
      FHotkeyEdits[FCaptureKind].Text := QSHotkeyModifiersText(Mods) + '...';
    Key := 0;
    KeyChar := #0;
    Exit;
  end;

  H.Modifiers := Mods;
  H.VirtualKey := Key;

  if not QSHotkeyIsValid(H) then
  begin
    SetHotkeyStatus(
      'Нужен модификатор: Ctrl, Alt, Shift или Win (кроме Print Screen, ' +
      'Scroll Lock и Pause).',
      True);
    Key := 0;
    KeyChar := #0;
    Exit;
  end;

  for Other := Low(TQSHotkeyKind) to High(TQSHotkeyKind) do
    if (Other <> FCaptureKind) and
       QSHotkeysEqual(H, FEditing.Hotkeys[Other]) then
    begin
      SetHotkeyStatus('Комбинация уже назначена: ' + QSHotkeyText(H), True);
      Key := 0;
      KeyChar := #0;
      Exit;
    end;

  { Проверяем, не занята ли комбинация другой программой, и по возможности
    подсказываем, какое приложение её удерживает. }
  if not QSHotkeyAvailableNow(H) then
  begin
    OwnerHint := QSHotkeyOwnerHint(H);
    if OwnerHint = '' then
      SetHotkeyStatus('Комбинация ' + QSHotkeyText(H) +
        ' занята другой программой или зарезервирована Windows.', True)
    else
      SetHotkeyStatus('Комбинация ' + QSHotkeyText(H) + ' занята. ' +
        OwnerHint + '.', True);
    Key := 0;
    KeyChar := #0;
    Exit;
  end;

  FEditing.Hotkeys[FCaptureKind] := H;
  EndHotkeyCapture;
  SetHotkeyStatus('Назначено: ' + QSHotkeyText(H), False);

  Key := 0;
  KeyChar := #0;
end;

procedure TQSSettingsForm.btnHotkeyClick(Sender: TObject);
begin
  if Sender is TButton then
    BeginHotkeyCapture(TQSHotkeyKind(Integer(TButton(Sender).Tag)));
end;

procedure TQSSettingsForm.btnResetHotkeysClick(Sender: TObject);
var
  K: TQSHotkeyKind;
begin
  if FEditing = nil then
    Exit;
  for K := Low(TQSHotkeyKind) to High(TQSHotkeyKind) do
    FEditing.Hotkeys[K] := QSDefaultHotkey(K);
  UpdateHotkeyEdits;
  SetHotkeyStatus('Восстановлены комбинации по умолчанию.', False);
end;

procedure TQSSettingsForm.NavChange(Sender: TObject);
begin
  if (FNav <> nil) and (FTabs <> nil) and (FNav.ItemIndex >= 0) and
     (FNav.ItemIndex < FTabs.TabCount) then
    FTabs.ActiveTab := FTabs.Tabs[FNav.ItemIndex];
end;

procedure TQSSettingsForm.btnBrowseClick(Sender: TObject);
var
  Dir: string;
begin
  if FEdFolder = nil then
    Exit;
  Dir := Trim(FEdFolder.Text);
  if Dir = '' then
    Dir := QSDefaultSaveFolder;
  if SelectDirectory('Выберите папку для сохранения снимков', '', Dir) then
    FEdFolder.Text := Dir;
end;

procedure TQSSettingsForm.cmbFormatChange(Sender: TObject);
begin
  UpdateQualityState;
end;

procedure TQSSettingsForm.tbQualityChange(Sender: TObject);
begin
  if FQualityValue <> nil then
    FQualityValue.Text := IntToStr(
      Integer(EnsureRange(Round(FQualityTrack.Value), 1, 100)));
end;

procedure TQSSettingsForm.btnSaveClick(Sender: TObject);
var
  Dir: string;
  K, P: TQSHotkeyKind;
begin
  if FEditing = nil then
    Exit;

  EndHotkeyCapture;

  Dir := Trim(FEdFolder.Text);
  if Dir = '' then
    Dir := QSDefaultSaveFolder;

  if not DirectoryExists(Dir) then
    if not ForceDirectories(Dir) then
    begin
      SelectPage(1);
      ShowMessage('Не удалось создать папку:' + sLineBreak + Dir);
      Exit;
    end;

  { На всякий случай проверяем уникальность комбинаций. Пустые и неполные
    комбинации не считаются дубликатами. }
  for K := qshkWindow to qshkDesktop do
    if QSHotkeyIsValid(FEditing.Hotkeys[K]) then
      for P := qshkRegion to Pred(K) do
        if QSHotkeyIsValid(FEditing.Hotkeys[P]) and
           QSHotkeysEqual(FEditing.Hotkeys[K], FEditing.Hotkeys[P]) then
        begin
          SelectPage(2);
          ShowMessage('Горячие клавиши не должны повторяться.');
          Exit;
        end;

  FEditing.SaveFolder := Dir;
  FEditing.SaveFormat := TQSImageFormat(
    EnsureRange(FCmbFormat.ItemIndex, 0, 1));
  FEditing.JpegQuality := Integer(
    EnsureRange(Round(FQualityTrack.Value), 1, 100));
  FEditing.OpenEditorAfterCapture := FChkEditor.IsChecked;
  FEditing.CopyAfterCapture := FChkCopy.IsChecked;
  FEditing.MinimizeToTray := FChkMinimizeToTray.IsChecked;
  FEditing.StartMinimized := FChkStartMinimized.IsChecked;
  FEditing.Autostart := FChkAutostart.IsChecked;
  FEditing.ShowNotifications := FChkNotifications.IsChecked;

  ModalResult := mrOk;
end;

procedure TQSSettingsForm.btnCancelClick(Sender: TObject);
begin
  EndHotkeyCapture;
  ModalResult := mrCancel;
end;

procedure TQSSettingsForm.FormResize(Sender: TObject);
begin
  if FBottomPanel = nil then
    Exit;

  if FBtnSave <> nil then
    FBtnSave.SetBounds(FBottomPanel.Width - 12 - 120, 14, 120, 34);
  if FBtnCancel <> nil then
    FBtnCancel.SetBounds(FBottomPanel.Width - 12 - 120 - 8 - 110, 14, 110, 34);
end;

procedure TQSSettingsForm.FormDeactivate(Sender: TObject);
begin
  if FCapturing then
  begin
    EndHotkeyCapture;
    SetHotkeyStatus('Захват комбинации отменён.', False);
  end;
end;

procedure TQSSettingsForm.FormDestroy(Sender: TObject);
begin
  FCapturing := False;
  FreeAndNil(FEditing);
end;

end.
