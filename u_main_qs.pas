unit u_main_qs;

{
  QS Click - главное окно и связка всех модулей.

  Что делает этот модуль:
    * строит интерфейс главного окна программно (без .fmx-компонентов);
    * вызывает захват области / активного окна / рабочего стола / монитора;
    * показывает последний снимок в окне предпросмотра;
    * открывает редактор, копирует снимок в буфер, сохраняет PNG/JPEG;
    * связывает приложение со значком в области уведомлений, горячими
      клавишами и отдельным окном настроек.

  Все публичные функции модуля (QSApp...), а также обработчики TForm1
  (btnRegionClick, btnWindowClick и т.д.) можно назначать кнопкам и пунктам
  меню в дизайнере или в коде.

  Курсор мыши в снимки не попадает.
}

{$WARN SYMBOL_PLATFORM OFF}

interface

uses
  System.SysUtils,
  System.Types,
  System.UITypes,
  System.Classes,
  System.Math,
  System.IOUtils,
  Winapi.Windows,
  { ВАЖНО: Winapi.Windows объявляет TBitmap = tagBITMAP.
    FMX.Graphics должен идти после Winapi.Windows, иначе TBitmap
    из FMX.Graphics затеняется и TBitmap.Create не компилируется. }
  FMX.Types,
  FMX.Controls,
  FMX.Forms,
  FMX.Graphics,
  FMX.Dialogs,
  FMX.StdCtrls,
  FMX.Objects,
  FMX.ListBox,
  FMX.Ani,
  { Нужен для ApplicationHWND: кнопка панели задач принадлежит служебному
    окну приложения, а не главному окну. См. SetTaskbarButtonVisible. }
  FMX.Platform.Win,
  u_qs_capture,
  u_qs_select,
  u_qs_editor,
  u_qs_settings,
  u_qs_tray;

type
  TForm1 = class(TForm)
  private
    FLastBitmap: TBitmap;
    FLastFileName: string;
    FSettings: TQSAppSettings;

    FUpdatingUI: Boolean;
    FCaptureInProgress: Boolean;
    FExiting: Boolean;
    FHiddenForCapture: Boolean;
    FEditorWasVisible: Boolean;
    FTrayHintShown: Boolean;
    FSettingsOpen: Boolean;
    FSettingsForm: TQSSettingsForm;
    FStartupTimer: TTimer;

    FTopPanel: TPanel;
    FBottomPanel: TPanel;
    FPreviewHost: TRectangle;
    FPreview: TImage;
    FPreviewFade: TFloatAnimation;
    FEmptyLabel: TLabel;
    FStatusLabel: TLabel;
    FHintLabel: TLabel;
    FInfoLabel: TLabel;

    FCmbMonitor: TComboBox;
    FBtnMonitor: TButton;

    procedure BuildUI;
    function NewLabel(AParent: TControl; const AText: string;
      AX, AY, AWidth, AHeight: Single; ABold: Boolean = False): TLabel;
    function NewButton(AParent: TControl; const AText: string;
      AX, AY, AWidth, AHeight: Single): TButton;

    procedure UpdateMonitorCombo;
    procedure UpdateHotkeyHint;
    procedure UpdatePreview;
    procedure UpdateInfo;
    procedure PlayPreviewFade;
    procedure SetStatus(const AText: string);
    procedure SetLastBitmap(ABitmap: TBitmap; const AFileName: string);
    function HasBitmap: Boolean;
    function EnsureSaveFolder: Boolean;
    function MakeDefaultFileName: string;

    function BeginCapture: Boolean;
    procedure EndCapture;
    procedure AfterCapture;
    procedure TrayAction(AAction: TQSTrayAction; AIndex: Integer);
    procedure StartupTimerTick(Sender: TObject);

    /// <summary>
    /// Показывает или убирает кнопку приложения на панели задач. Кнопку
    /// создаёт служебное окно FireMonkey (TFMAppClass, ApplicationHWND), а
    /// главное окно является его owned-окном и своей кнопки не имеет.
    /// Поэтому при скрытии в трей служебное окно прячется, а при показе
    /// возвращается на место.
    /// </summary>
    procedure SetTaskbarButtonVisible(AVisible: Boolean);

  public
    /// <summary>Снимок произвольной области (интерактивное выделение).</summary>
    function CaptureRegion: Boolean;
    /// <summary>Снимок активного (переднего) окна другого приложения.</summary>
    function CaptureActiveWindow: Boolean;
    /// <summary>Снимок всего виртуального рабочего стола (все мониторы).</summary>
    function CaptureDesktop: Boolean;
    /// <summary>Снимок одного монитора по индексу.</summary>
    function CaptureMonitor(AIndex: Integer): Boolean;

    /// <summary>Копирование последнего снимка в буфер обмена.</summary>
    function CopyLast: Boolean;
    /// <summary>Сохранение последнего снимка в PNG/JPEG через диалог.</summary>
    function SaveLast: Boolean;
    /// <summary>Открытие последнего снимка в редакторе.</summary>
    procedure EditLast;

    /// <summary>Скрыть главное окно в область уведомлений.</summary>
    procedure HideToTray;
    /// <summary>Показать главное окно из области уведомлений.</summary>
    procedure ShowMainWindow;
    /// <summary>Открыть отдельное окно настроек.</summary>
    procedure ShowSettings;
    /// <summary>Завершить приложение (в том числе из трея).</summary>
    procedure ExitApplication;

  published
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormResize(Sender: TObject);

    procedure btnRegionClick(Sender: TObject);
    procedure btnWindowClick(Sender: TObject);
    procedure btnDesktopClick(Sender: TObject);
    procedure btnMonitorClick(Sender: TObject);
    procedure btnEditClick(Sender: TObject);
    procedure btnCopyClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
    procedure btnTrayClick(Sender: TObject);
    procedure btnSettingsClick(Sender: TObject);
    procedure btnExitClick(Sender: TObject);

    procedure cmbMonitorChange(Sender: TObject);
  end;

var
  Form1: TForm1;

{ ------------------------------------------------------------------ }
{ Функции уровня модуля                                              }
{ Их удобно назначать пунктам меню, кнопкам на других формах и т.п.  }
{ ------------------------------------------------------------------ }

/// <summary>Снимок области. Возвращает True, если снимок сделан.</summary>
function QSAppCaptureRegion: Boolean;
/// <summary>Снимок активного окна.</summary>
function QSAppCaptureWindow: Boolean;
/// <summary>Снимок всего рабочего стола.</summary>
function QSAppCaptureDesktop: Boolean;
/// <summary>Снимок монитора по индексу (0 - первый).</summary>
function QSAppCaptureMonitor(AIndex: Integer): Boolean;
/// <summary>Редактор последнего снимка.</summary>
procedure QSAppEditLast;
/// <summary>Копирование последнего снимка в буфер обмена.</summary>
function QSAppCopyLast: Boolean;
/// <summary>Сохранение последнего снимка через диалог.</summary>
function QSAppSaveLast: Boolean;
/// <summary>Показать главное окно.</summary>
procedure QSAppShowMainWindow;
/// <summary>Открыть окно настроек.</summary>
procedure QSAppShowSettings;
/// <summary>Скрыть главное окно в трей.</summary>
procedure QSAppHideToTray;
/// <summary>Выход из приложения.</summary>
procedure QSAppExit;

implementation

{$R *.fmx}

{ ------------------------------------------------------------------ }
{ Вспомогательные функции                                           }
{ ------------------------------------------------------------------ }

{ ------------------------------------------------------------------ }
{ Создание интерфейса                                                }
{ ------------------------------------------------------------------ }

procedure TForm1.FormCreate(Sender: TObject);
var
  Conflict: string;
begin
  FLastBitmap := nil;
  FLastFileName := '';
  FSettingsForm := nil;
  FStartupTimer := nil;
  FPreviewFade := nil;

  FUpdatingUI := False;
  FCaptureInProgress := False;
  FExiting := False;
  FHiddenForCapture := False;
  FEditorWasVisible := False;
  FTrayHintShown := False;
  FSettingsOpen := False;

  FSettings := TQSAppSettings.Create;
  FSettings.Load;
  { Общая ссылка для остальных модулей (в частности, редактора снимков):
    диалоги сохранения должны видеть один и тот же объект настроек. }
  QSGlobalSettings := FSettings;
  QSEnsureAboutFile;

  FUpdatingUI := True;
  try
    BuildUI;
    UpdateHotkeyHint;
    UpdateMonitorCombo;
    UpdatePreview;
  finally
    FUpdatingUI := False;
  end;

  QSTrayInitialize(TrayAction, FSettings.Hotkeys);
  QSTraySetMonitorCount(Length(QSMonitorList));

  if not QSTrayReady then
    SetStatus('Не удалось создать значок в области уведомлений.')
  else if not QSTrayHotkeysActive then
  begin
    Conflict := QSTrayLastHotkeyConflict;
    if Conflict <> '' then
      Conflict := ' (' + Conflict + ')';
    SetStatus('Не удалось назначить горячие клавиши: возможно, их заняла другая программа.');
    QSTrayShowBalloon(QSAppCaption,
      'Не удалось назначить горячие клавиши' + Conflict +
      '. Откройте «Настройки» и выберите другие комбинации.');
  end;

  { Запуск свёрнутым выполняем после того, как Application.Run покажет
    главное окно. Иначе FMX снова сделает форму видимой. }
  if FSettings.StartMinimized then
  begin
    FStartupTimer := TTimer.Create(Self);
    FStartupTimer.Interval := 350;
    FStartupTimer.OnTimer := StartupTimerTick;
  end;
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  if FStartupTimer <> nil then
  begin
    FStartupTimer.Enabled := False;
    FreeAndNil(FStartupTimer);
  end;

  if FSettings <> nil then
    FSettings.Save;
  QSTrayFinalize;

  FreeAndNil(FLastBitmap);
  { Снимаем ссылку до освобождения объекта настроек. }
  QSGlobalSettings := nil;
  FreeAndNil(FSettings);
end;

procedure TForm1.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if FSettings = nil then
  begin
    CanClose := True;
    Exit;
  end;

  if FExiting or Application.Terminated then
  begin
    if FSettings <> nil then
      FSettings.Save;
    CanClose := True;
    Exit;
  end;

  { Если значок в трее недоступен, скрывать окно нельзя: вернуть его
    будет нечем. В этом случае приложение закрывается обычным образом. }
  if FSettings.MinimizeToTray and QSTrayReady then
  begin
    CanClose := False;
    HideToTray;
    Exit;
  end;

  FSettings.Save;
  CanClose := True;
end;

procedure TForm1.FormResize(Sender: TObject);
begin
  if (FHintLabel <> nil) and (FTopPanel <> nil) and (FTopPanel.Width > 700) then
  begin
    FHintLabel.SetBounds(12, 50, FTopPanel.Width - 356, 44);
    if FInfoLabel <> nil then
      FInfoLabel.SetBounds(FTopPanel.Width - 332, 50, 320, 44);
  end;

  { Если включено «Скрывать в трей», обычное сворачивание окна тоже
    убирает его с панели задач. Вернуть окно можно двойным щелчком
    по значку в области уведомлений. }
  if (FSettings <> nil) and FSettings.MinimizeToTray and QSTrayReady and
     (WindowState = TWindowState.wsMinimized) and Visible then
    HideToTray;
end;

procedure TForm1.StartupTimerTick(Sender: TObject);
begin
  if FStartupTimer <> nil then
    FStartupTimer.Enabled := False;

  if FSettingsOpen then
    Exit;

  if (FSettings <> nil) and FSettings.StartMinimized then
  begin
    if QSTrayReady then
      HideToTray
    else
      SetStatus('Окно оставлено на экране: значок в области уведомлений недоступен.');
  end;
end;

function TForm1.NewLabel(AParent: TControl; const AText: string;
  AX, AY, AWidth, AHeight: Single; ABold: Boolean): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(AX, AY, AWidth, AHeight);
  Result.AutoSize := False;
  Result.TextAlign := TTextAlign.Leading;
  Result.VertTextAlign := TTextAlign.Center;
  Result.WordWrap := False;
  Result.HitTest := False;
  Result.Text := AText;

  { Размер и начертание задаём сами, а не берём из стиля. }
  Result.StyledSettings := Result.StyledSettings -
    [TStyledSetting.Size, TStyledSetting.Style];

  if ABold then
    Result.Font.Style := [TFontStyle.fsBold];
end;

function TForm1.NewButton(AParent: TControl; const AText: string;
  AX, AY, AWidth, AHeight: Single): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(AX, AY, AWidth, AHeight);
  Result.Text := AText;
end;

procedure TForm1.BuildUI;
var
  W, H: Single;
  B: TButton;
begin
  Caption := QSAppTitle;
  BorderStyle := TFmxFormBorderStyle.Sizeable;
  Constraints.MinWidth := 900;
  Constraints.MinHeight := 560;

  if Screen <> nil then
  begin
    W := Screen.WorkAreaRect.Width - 60;
    H := Screen.WorkAreaRect.Height - 60;
    if W > 1180 then
      W := 1180;
    if W < 900 then
      W := 900;
    if H > 700 then
      H := 700;
    if H < 560 then
      H := 560;
    { У TForm свойства Width/Height целочисленные, а WorkAreaRect
      возвращает TRectF, поэтому размеры округляем. }
    Width := Round(W);
    Height := Round(H);
  end;

  Position := TFormPosition.ScreenCenter;

  { ---------------- Верхняя панель: снимки ---------------- }
  FTopPanel := TPanel.Create(Self);
  FTopPanel.Parent := Self;
  FTopPanel.Align := TAlignLayout.Top;
  FTopPanel.Height := 104;

  B := NewButton(FTopPanel, 'Снимок области', 12, 10, 160, 34);
  B.OnClick := btnRegionClick;

  B := NewButton(FTopPanel, 'Активное окно', 180, 10, 160, 34);
  B.OnClick := btnWindowClick;

  B := NewButton(FTopPanel, 'Весь рабочий стол', 348, 10, 170, 34);
  B.OnClick := btnDesktopClick;

  FBtnMonitor := NewButton(FTopPanel, 'Снимок монитора', 526, 10, 150, 34);
  FBtnMonitor.OnClick := btnMonitorClick;

  FCmbMonitor := TComboBox.Create(Self);
  FCmbMonitor.Parent := FTopPanel;
  FCmbMonitor.SetBounds(684, 12, 208, 30);
  FCmbMonitor.OnChange := cmbMonitorChange;

  FHintLabel := NewLabel(FTopPanel,
    'Горячие клавиши: Ctrl+Shift+1 - область, Ctrl+Shift+2 - активное окно, ' +
    'Ctrl+Shift+3 - весь рабочий стол. Снимки делаются без курсора мыши.',
    12, 50, 540, 44);
  FHintLabel.WordWrap := True;

  FInfoLabel := NewLabel(FTopPanel, 'Снимков пока нет.',
    568, 50, 320, 44);
  FInfoLabel.WordWrap := True;
  FInfoLabel.VertTextAlign := TTextAlign.Leading;

  { ---------------- Нижняя панель: действия ---------------- }
  FBottomPanel := TPanel.Create(Self);
  FBottomPanel.Parent := Self;
  FBottomPanel.Align := TAlignLayout.Bottom;
  FBottomPanel.Height := 90;

  B := NewButton(FBottomPanel, 'Редактировать', 12, 10, 150, 36);
  B.OnClick := btnEditClick;

  B := NewButton(FBottomPanel, 'Копировать', 170, 10, 130, 36);
  B.OnClick := btnCopyClick;

  B := NewButton(FBottomPanel, 'Сохранить...', 308, 10, 130, 36);
  B.OnClick := btnSaveClick;

  B := NewButton(FBottomPanel, 'Свернуть в трей', 446, 10, 150, 36);
  B.OnClick := btnTrayClick;

  B := NewButton(FBottomPanel, 'Настройки...', 604, 10, 140, 36);
  B.OnClick := btnSettingsClick;

  B := NewButton(FBottomPanel, 'Выход', 752, 10, 100, 36);
  B.OnClick := btnExitClick;

  FStatusLabel := NewLabel(FBottomPanel, 'Готов к работе.', 12, 54, 800, 26);
  FStatusLabel.Align := TAlignLayout.Bottom;
  FStatusLabel.Height := 26;
  FStatusLabel.Margins.Left := 12;
  FStatusLabel.Margins.Right := 12;
  FStatusLabel.Margins.Bottom := 6;

  { ---------------- Область предпросмотра ---------------- }
  FPreviewHost := TRectangle.Create(Self);
  FPreviewHost.Parent := Self;
  FPreviewHost.Align := TAlignLayout.Client;
  FPreviewHost.Fill.Color := $FF1E1E22;
  FPreviewHost.Stroke.Kind := TBrushKind.None;

  FPreview := TImage.Create(Self);
  FPreview.Parent := FPreviewHost;
  FPreview.Align := TAlignLayout.Client;
  FPreview.Margins.Left := 12;
  FPreview.Margins.Top := 12;
  FPreview.Margins.Right := 12;
  FPreview.Margins.Bottom := 12;
  FPreview.WrapMode := TImageWrapMode.Fit;
  FPreview.HitTest := False;

  { Лёгкое появление нового снимка в предпросмотре (анимация FireMonkey). }
  FPreviewFade := TFloatAnimation.Create(Self);
  FPreviewFade.Parent := FPreview;
  FPreviewFade.PropertyName := 'Opacity';
  FPreviewFade.Duration := 0.25;
  FPreviewFade.StartValue := 0.4;
  FPreviewFade.StopValue := 1;

  FEmptyLabel := NewLabel(FPreviewHost,
    'Снимков пока нет.' + sLineBreak +
    'Выберите действие на верхней панели.',
    0, 0, 520, 80);
  FEmptyLabel.Align := TAlignLayout.Center;
  FEmptyLabel.TextAlign := TTextAlign.Center;
  FEmptyLabel.WordWrap := True;
  FEmptyLabel.StyledSettings := FEmptyLabel.StyledSettings -
    [TStyledSetting.FontColor];
  FEmptyLabel.FontColor := $FF9A9AA2;
  FEmptyLabel.Font.Size := 16;

  FormResize(Self);
end;

{ ------------------------------------------------------------------ }
{ Настройки                                                          }
{ ------------------------------------------------------------------ }

procedure TForm1.UpdateHotkeyHint;
begin
  if (FHintLabel = nil) or (FSettings = nil) then
    Exit;

  FHintLabel.Text := Format(
    'Горячие клавиши: %s - область, %s - активное окно, %s - весь рабочий ' +
    'стол. Снимки делаются без курсора мыши.',
    [QSHotkeyText(FSettings.Hotkeys[qshkRegion]),
     QSHotkeyText(FSettings.Hotkeys[qshkWindow]),
     QSHotkeyText(FSettings.Hotkeys[qshkDesktop])]);
end;

procedure TForm1.ShowSettings;
var
  Dlg: TQSSettingsForm;
  Ed: TQSEditorForm;
  OldHotkeys: TQSHotkeys;
  Accepted: Boolean;
  Resumed: Boolean;
  EdWasVisible: Boolean;
  Conflict: string;
begin
  if FSettingsOpen or FCaptureInProgress then
    Exit;

  if FStartupTimer <> nil then
    FStartupTimer.Enabled := False;

  FSettingsOpen := True;
  OldHotkeys := FSettings.Hotkeys;
  Accepted := False;
  Resumed := True;

  Ed := QSActiveEditor;
  EdWasVisible := (Ed <> nil) and Ed.Visible;

  Dlg := TQSSettingsForm.CreateNew(Application);
  FSettingsForm := Dlg;
  try
    { Редактор всегда StayOnTop. На время модальных настроек его нужно
      спрятать, иначе он перекроет диалог и работать с ним будет нельзя.
      После закрытия настроек вернём редактор на место. }
    if EdWasVisible then
      Ed.Hide;

    Dlg.Initialize(FSettings);

    { Пока открыто окно настроек, глобальные комбинации не должны
      запускать захват: их можно свободно переназначать. }
    QSTraySuspendHotkeys;
    try
      Accepted := Dlg.ShowModal = mrOk;
      if Accepted then
        FSettings.Assign(Dlg.Settings);
    finally
      Resumed := QSTrayResumeHotkeys;
    end;
  finally
    if EdWasVisible and (Ed <> nil) and not Ed.Visible then
    begin
      Ed.Show;
      Ed.BringToFront;
    end;
    FSettingsForm := nil;
    Dlg.Free;
    FSettingsOpen := False;
  end;

  if not Accepted then
  begin
    if not Resumed then
    begin
      Conflict := QSTrayLastHotkeyConflict;
      SetStatus('Не удалось вернуть прежние горячие клавиши.');
      if Conflict <> '' then
        ShowMessage('Прежние горячие клавиши вернуть не удалось (' + Conflict +
          '). Откройте настройки и назначьте другие комбинации.')
      else
        ShowMessage('Прежние горячие клавиши заняла другая программа. ' +
          'Откройте настройки и назначьте другие комбинации.');
    end;
    Exit;
  end;

  if not QSTrayApplyHotkeys(FSettings.Hotkeys) then
  begin
    { TQSTray.SetHotkeys уже попытался вернуть прежний набор. }
    FSettings.Hotkeys := OldHotkeys;
    Conflict := QSTrayLastHotkeyConflict;
    if Conflict = '' then
      Conflict := 'занята другой программой';
    if not QSTrayReady then
      ShowMessage('Значок в области уведомлений недоступен, поэтому глобальные ' +
        'горячие клавиши не работают. Остальные настройки сохранены.')
    else if QSTrayHotkeysActive then
      ShowMessage('Не удалось назначить горячую клавишу ' + Conflict +
        '. Оставлены прежние комбинации.')
    else
      ShowMessage('Не удалось назначить новые горячие клавиши (' + Conflict +
        '), а прежние комбинации восстановить не удалось. Глобальные клавиши ' +
        'временно не работают - назначьте другие комбинации в настройках.');
  end;

  if not QSSetAutostart(FSettings.Autostart) then
  begin
    FSettings.Autostart := QSAutostartEnabled;
    ShowMessage('Не удалось изменить автозапуск в реестре Windows.');
  end;

  FSettings.Save;
  UpdateHotkeyHint;
  UpdateMonitorCombo;
  SetStatus('Настройки сохранены.');
end;

procedure TForm1.UpdateMonitorCombo;
var
  Monitors: TArray<TQSMonitorInfo>;
  I: Integer;
  PrevUpdating: Boolean;
begin
  if FCmbMonitor = nil then
    Exit;

  PrevUpdating := FUpdatingUI;
  FUpdatingUI := True;
  try
    FCmbMonitor.Items.BeginUpdate;
    try
      FCmbMonitor.Items.Clear;
      Monitors := QSMonitorList;
      for I := 0 to High(Monitors) do
      begin
        if Monitors[I].Primary then
          FCmbMonitor.Items.Add(Format('Монитор %d: %d x %d (основной)',
            [I + 1, Monitors[I].Bounds.Width, Monitors[I].Bounds.Height]))
        else
          FCmbMonitor.Items.Add(Format('Монитор %d: %d x %d',
            [I + 1, Monitors[I].Bounds.Width, Monitors[I].Bounds.Height]));
      end;
    finally
      FCmbMonitor.Items.EndUpdate;
    end;

    if FSettings.LastMonitorIndex >= Length(Monitors) then
      FSettings.LastMonitorIndex := 0;

    if Length(Monitors) > 0 then
      FCmbMonitor.ItemIndex := FSettings.LastMonitorIndex
    else
      FCmbMonitor.ItemIndex := -1;

    FCmbMonitor.Enabled := Length(Monitors) > 0;
    if FBtnMonitor <> nil then
      FBtnMonitor.Enabled := Length(Monitors) > 0;
  finally
    FUpdatingUI := PrevUpdating;
  end;

  QSTraySetMonitorCount(Length(Monitors));
end;

procedure TForm1.UpdatePreview;
begin
  if FPreview = nil then
    Exit;

  if not HasBitmap then
  begin
    FPreview.Bitmap.SetSize(0, 0);
    if FEmptyLabel <> nil then
      FEmptyLabel.Visible := True;
  end
  else
  begin
    FPreview.Bitmap.Assign(FLastBitmap);
    if FEmptyLabel <> nil then
      FEmptyLabel.Visible := False;
  end;

  UpdateInfo;
end;

procedure TForm1.PlayPreviewFade;
begin
  if FPreviewFade = nil then
    Exit;
  FPreviewFade.StartValue := 0.4;
  FPreviewFade.StopValue := 1;
  FPreviewFade.Start;
end;

procedure TForm1.UpdateInfo;
begin
  if FInfoLabel = nil then
    Exit;

  if not HasBitmap then
  begin
    FInfoLabel.Text := 'Снимков пока нет.';
    Exit;
  end;

  FInfoLabel.Text := Format('Размер: %d x %d' + sLineBreak + 'Файл: %s',
    [FLastBitmap.Width, FLastBitmap.Height, FLastFileName]);
end;

procedure TForm1.SetStatus(const AText: string);
begin
  if FStatusLabel <> nil then
    FStatusLabel.Text := AText;
end;

procedure TForm1.SetLastBitmap(ABitmap: TBitmap; const AFileName: string);
begin
  if ABitmap = nil then
    Exit;

  FreeAndNil(FLastBitmap);
  FLastBitmap := ABitmap;
  FLastFileName := AFileName;
  UpdatePreview;
  PlayPreviewFade;
end;

function TForm1.HasBitmap: Boolean;
begin
  Result := (FLastBitmap <> nil) and not FLastBitmap.IsEmpty;
end;

function TForm1.EnsureSaveFolder: Boolean;
begin
  if Trim(FSettings.SaveFolder) = '' then
    FSettings.SaveFolder := QSDefaultSaveFolder;

  if DirectoryExists(FSettings.SaveFolder) then
  begin
    Result := True;
    Exit;
  end;

  Result := ForceDirectories(FSettings.SaveFolder);
end;

function TForm1.MakeDefaultFileName: string;
var
  Base, Ext: string;
  N: Integer;
begin
  if not EnsureSaveFolder then
    FSettings.SaveFolder := QSDefaultSaveFolder;

  if FSettings.SaveFormat = qsifJpeg then
    Ext := '.jpg'
  else
    Ext := '.png';

  Base := QSAppCaption + '_' + FormatDateTime('yyyy-mm-dd_hh-nn-ss', Now);
  Result := System.IOUtils.TPath.Combine(FSettings.SaveFolder, Base + Ext);

  N := 1;
  while FileExists(Result) do
  begin
    Result := System.IOUtils.TPath.Combine(FSettings.SaveFolder,
      Base + '_' + IntToStr(N) + Ext);
    Inc(N);
  end;
end;

{ ------------------------------------------------------------------ }
{ Захват экрана                                                      }
{ ------------------------------------------------------------------ }

function TForm1.BeginCapture: Boolean;
var
  Ed: TQSEditorForm;
begin
  Result := False;
  if FCaptureInProgress then
    Exit;

  { Пользователь уже начал работу: отложенное сворачивание при запуске
    больше не нужно. }
  if FStartupTimer <> nil then
    FStartupTimer.Enabled := False;

  FCaptureInProgress := True;
  FHiddenForCapture := False;
  FEditorWasVisible := False;

  { Редактор всегда поверх остальных окон, поэтому на время снимка
    его тоже нужно спрятать, иначе он попадёт в кадр. }
  Ed := QSActiveEditor;
  if (Ed <> nil) and Ed.Visible and
     (Ed.WindowState <> TWindowState.wsMinimized) then
  begin
    FEditorWasVisible := True;
    Ed.Hide;
  end;

  if Visible and (WindowState <> TWindowState.wsMinimized) then
  begin
    FHiddenForCapture := True;
    Hide;
  end;

  { Даём Windows время убрать окна с экрана. }
  Application.ProcessMessages;
  Sleep(180);
  Application.ProcessMessages;

  Result := True;
end;

procedure TForm1.EndCapture;
var
  Ed: TQSEditorForm;
begin
  Ed := QSActiveEditor;
  if FEditorWasVisible and (Ed <> nil) and not Ed.Visible then
  begin
    Ed.Show;
    Ed.BringToFront;
  end;

  if FHiddenForCapture then
  begin
    if WindowState = TWindowState.wsMinimized then
      WindowState := TWindowState.wsNormal;
    Show;
    BringToFront;
  end;

  FHiddenForCapture := False;
  FEditorWasVisible := False;
  FCaptureInProgress := False;
end;

procedure TForm1.AfterCapture;
begin
  UpdatePreview;

  if not HasBitmap then
  begin
    SetStatus('Снимок не сделан.');
    Exit;
  end;

  if FSettings.CopyAfterCapture then
  begin
    if QSCopyBitmapToClipboard(FLastBitmap) then
      SetStatus('Снимок скопирован в буфер обмена.')
    else
      SetStatus('Не удалось скопировать снимок в буфер обмена.');
  end
  else
    SetStatus(Format('Снимок готов: %d x %d. Файл: %s',
      [FLastBitmap.Width, FLastBitmap.Height,
       ExtractFileName(FLastFileName)]));

  if FSettings.ShowNotifications and QSTrayReady and not FHiddenForCapture and
     ((not Visible) or (WindowState = TWindowState.wsMinimized)) then
    QSTrayShowBalloon(QSAppCaption,
      Format('Снимок готов: %d x %d', [FLastBitmap.Width, FLastBitmap.Height]));

  if FSettings.OpenEditorAfterCapture then
    QSShowEditor(FLastBitmap, FLastFileName);
end;

function TForm1.CaptureRegion: Boolean;
var
  ScreenRect: TRect;
  B: TBitmap;
begin
  Result := False;
  if not BeginCapture then
    Exit;

  try
    B := nil;
    try
      B := QSSelectScreenRegion(ScreenRect);
      if B = nil then
      begin
        SetStatus('Снимок области отменён.');
        Exit;
      end;

      SetLastBitmap(B, MakeDefaultFileName);
      B := nil;
      Result := True;
    finally
      B.Free;
    end;

    AfterCapture;
  finally
    EndCapture;
  end;
end;

function TForm1.CaptureActiveWindow: Boolean;
var
  Bounds: TRect;
  B: TBitmap;
begin
  Result := False;
  if not BeginCapture then
    Exit;

  try
    B := nil;
    try
      B := QSCaptureForegroundWindow(Bounds);
      if B = nil then
      begin
        SetStatus('Не удалось определить активное окно.');
        Exit;
      end;

      SetLastBitmap(B, MakeDefaultFileName);
      B := nil;
      Result := True;
    finally
      B.Free;
    end;

    AfterCapture;
  finally
    EndCapture;
  end;
end;

function TForm1.CaptureDesktop: Boolean;
var
  B: TBitmap;
begin
  Result := False;
  if not BeginCapture then
    Exit;

  try
    B := nil;
    try
      B := QSCaptureDesktop;
      if B = nil then
      begin
        SetStatus('Не удалось снять рабочий стол.');
        Exit;
      end;

      SetLastBitmap(B, MakeDefaultFileName);
      B := nil;
      Result := True;
    finally
      B.Free;
    end;

    AfterCapture;
  finally
    EndCapture;
  end;
end;

function TForm1.CaptureMonitor(AIndex: Integer): Boolean;
var
  Bounds: TRect;
  B: TBitmap;
begin
  Result := False;
  if not BeginCapture then
    Exit;

  try
    B := nil;
    try
      B := QSCaptureMonitor(AIndex, Bounds);
      if B = nil then
      begin
        SetStatus('Не удалось снять выбранный монитор.');
        Exit;
      end;

      SetLastBitmap(B, MakeDefaultFileName);
      B := nil;
      Result := True;
    finally
      B.Free;
    end;

    AfterCapture;
  finally
    EndCapture;
  end;
end;

{ ------------------------------------------------------------------ }
{ Действия с последним снимком                                       }
{ ------------------------------------------------------------------ }

function TForm1.CopyLast: Boolean;
begin
  Result := False;

  if not HasBitmap then
  begin
    ShowMessage('Сначала сделайте снимок экрана.');
    Exit;
  end;

  Result := QSCopyBitmapToClipboard(FLastBitmap);
  if Result then
    SetStatus('Снимок скопирован в буфер обмена.')
  else
    ShowMessage('Не удалось скопировать снимок в буфер обмена.');
end;

function TForm1.SaveLast: Boolean;
var
  Dlg: TSaveDialog;
  FileName, Ext: string;
begin
  Result := False;

  if not HasBitmap then
  begin
    ShowMessage('Сначала сделайте снимок экрана.');
    Exit;
  end;

  EnsureSaveFolder;
  if FLastFileName = '' then
    FLastFileName := MakeDefaultFileName;

  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Title := 'Сохранить снимок';
    Dlg.Filter := 'PNG (*.png)|*.png|JPEG (*.jpg; *.jpeg)|*.jpg;*.jpeg';

    if FSettings.SaveFormat = qsifJpeg then
    begin
      Dlg.FilterIndex := 2;
      Dlg.DefaultExt := 'jpg';
    end
    else
    begin
      Dlg.FilterIndex := 1;
      Dlg.DefaultExt := 'png';
    end;

    Dlg.Options := Dlg.Options + [TOpenOption.ofOverwritePrompt];

    { Диалог открывается в последнем использованном каталоге, а в поле
      имени файла выводится только имя, без полного пути. Если каталог
      исчез или ещё не задан — откат на штатную папку сохранения. }
    Dlg.InitialDir := FSettings.LastSaveDir;
    if not DirectoryExists(Dlg.InitialDir) then
      Dlg.InitialDir := FSettings.SaveFolder;
    if not DirectoryExists(Dlg.InitialDir) then
      Dlg.InitialDir := QSDefaultSaveFolder;
    Dlg.FileName := ExtractFileName(FLastFileName);

    if not Dlg.Execute then
      Exit;

    FileName := Dlg.FileName;
    Ext := LowerCase(ExtractFileExt(FileName));
    if (Ext <> '.png') and (Ext <> '.jpg') and (Ext <> '.jpeg') then
    begin
      if Dlg.FilterIndex = 2 then
        FileName := FileName + '.jpg'
      else
        FileName := FileName + '.png';
    end;

    if QSSaveBitmap(FLastBitmap, FileName, FSettings.JpegQuality) then
    begin
      FLastFileName := FileName;

      { Запоминаем каталог, в который реально сохранён файл (пользователь
        мог уйти в другую папку), и сразу пишем настройки в settings.ini:
        следующий диалог откроется именно здесь. }
      FSettings.LastSaveDir := ExtractFileDir(FileName);
      FSettings.Save;

      UpdateInfo;
      SetStatus('Сохранено: ' + FileName);
      Result := True;
    end
    else
      ShowMessage('Не удалось сохранить файл. Проверьте папку и права доступа.');
  finally
    Dlg.Free;
  end;
end;

procedure TForm1.EditLast;
begin
  if not HasBitmap then
  begin
    ShowMessage('Сначала сделайте снимок экрана.');
    Exit;
  end;

  QSShowEditor(FLastBitmap, FLastFileName);
  SetStatus('Снимок открыт в редакторе.');
end;

{ ------------------------------------------------------------------ }
{ Трей и системные действия                                          }
{ ------------------------------------------------------------------ }

procedure TForm1.SetTaskbarButtonVisible(AVisible: Boolean);
var
  Wnd: HWND;
  ExStyle: NativeInt;
begin
  if csDesigning in ComponentState then
    Exit;

  { Важно: кнопку на панели задач создаёт не главное окно, а служебное
    окно приложения с классом TFMAppClass (ApplicationHWND). Именно у него
    ex-стиль WS_EX_APPWINDOW, тогда как окно формы FMX создаётся как
    owned-окно этого служебного окна и своей кнопки в панели задач не имеет.
    Поэтому менять стиль главного окна бесполезно: управлять нужно
    служебным окном. }
  Wnd := ApplicationHWND;
  if Wnd = 0 then
    Exit;

  ExStyle := GetWindowLongPtr(Wnd, GWL_EXSTYLE);
  if AVisible then
    { Обычное состояние: служебное окно снова становится окном панели
      задач, и при показе Windows создаёт для приложения кнопку. }
    ExStyle := (ExStyle or WS_EX_APPWINDOW) and not WS_EX_TOOLWINDOW
  else
    { Состояние «в трее»: окно-утилита не попадает ни в панель задач,
      ни в Alt+Tab, даже если его кто-то снова покажет. }
    ExStyle := (ExStyle and not WS_EX_APPWINDOW) or WS_EX_TOOLWINDOW;

  { Применяем ex-стиль, не меняя положение, размер и Z-порядок окна. }
  SetWindowLongPtr(Wnd, GWL_EXSTYLE, ExStyle);
  SetWindowPos(Wnd, 0, 0, 0, 0, 0,
    SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE or
    SWP_FRAMECHANGED);

  if AVisible then
    { Служебное окно имеет размер 0x0 и расположено в углу экрана:
      показываем его без активации, чтобы панель задач заново создала
      кнопку приложения. }
    ShowWindow(Wnd, SW_SHOWNOACTIVATE)
  else
    { Скрытое окно гарантированно не оставляет кнопку на панели задач:
      одной смены ex-стиля для этого недостаточно. }
    ShowWindow(Wnd, SW_HIDE);
end;

procedure TForm1.HideToTray;
begin
  if not Visible then
    Exit;

  { Без значка в трее скрытое окно невозможно вернуть. }
  if not QSTrayReady then
  begin
    SetStatus('Значок в области уведомлений недоступен: окно оставлено на экране.');
    Exit;
  end;

  { Скрываем главное окно, а затем служебное окно приложения: иначе
    панель задач продолжает показывать кнопку, хотя самого окна на экране
    нет. }
  Hide;
  SetTaskbarButtonVisible(False);

  if FSettings.ShowNotifications and QSTrayReady and not FTrayHintShown then
  begin
    FTrayHintShown := True;
    QSTrayShowBalloon(QSAppCaption,
      'Приложение свёрнуто в область уведомлений. ' +
      'Двойной щелчок по значку откроет окно.');
  end;
end;

procedure TForm1.ShowMainWindow;
begin
  if FStartupTimer <> nil then
    FStartupTimer.Enabled := False;

  if FSettingsOpen and (FSettingsForm <> nil) then
  begin
    FSettingsForm.BringToFront;
    Exit;
  end;

  { Возвращаем окну кнопку на панели задач до того, как оно станет видимым. }
  SetTaskbarButtonVisible(True);

  if WindowState = TWindowState.wsMinimized then
    WindowState := TWindowState.wsNormal;

  Show;
  BringToFront;
  UpdateMonitorCombo;
end;

procedure TForm1.ExitApplication;
begin
  if FExiting then
    Exit;

  FExiting := True;

  if FStartupTimer <> nil then
    FStartupTimer.Enabled := False;

  if FSettings <> nil then
    FSettings.Save;

  { Явное завершение: FormDestroy сохранит настройки и уберёт значок
    из области уведомлений. FormCloseQuery при Terminate не вызывается. }
  Application.Terminate;
end;

procedure TForm1.TrayAction(AAction: TQSTrayAction; AIndex: Integer);
begin
  if FSettingsOpen then
  begin
    if (AAction = qstaShowMain) and (FSettingsForm <> nil) then
      FSettingsForm.BringToFront;
    Exit;
  end;

  { Пока идёт захват, новые команды не принимаем: оверлей и редактор
    уже работают, окно трогать нельзя. }
  if FCaptureInProgress then
    Exit;

  case AAction of
    qstaCaptureRegion: CaptureRegion;
    qstaCaptureWindow: CaptureActiveWindow;
    qstaCaptureDesktop: CaptureDesktop;
    qstaCaptureMonitor: CaptureMonitor(AIndex);
    qstaShowMain: ShowMainWindow;
    qstaSettings: ShowSettings;
    qstaExit: ExitApplication;
  end;
end;

{ ------------------------------------------------------------------ }
{ Обработчики интерфейса                                             }
{ ------------------------------------------------------------------ }

procedure TForm1.btnRegionClick(Sender: TObject);
begin
  CaptureRegion;
end;

procedure TForm1.btnWindowClick(Sender: TObject);
begin
  CaptureActiveWindow;
end;

procedure TForm1.btnDesktopClick(Sender: TObject);
begin
  CaptureDesktop;
end;

procedure TForm1.btnMonitorClick(Sender: TObject);
begin
  if (FCmbMonitor <> nil) and (FCmbMonitor.ItemIndex >= 0) then
    CaptureMonitor(FCmbMonitor.ItemIndex)
  else
    ShowMessage('Мониторы не найдены.');
end;

procedure TForm1.btnEditClick(Sender: TObject);
begin
  EditLast;
end;

procedure TForm1.btnCopyClick(Sender: TObject);
begin
  CopyLast;
end;

procedure TForm1.btnSaveClick(Sender: TObject);
begin
  SaveLast;
end;

procedure TForm1.btnTrayClick(Sender: TObject);
begin
  HideToTray;
end;

procedure TForm1.btnSettingsClick(Sender: TObject);
begin
  ShowSettings;
end;

procedure TForm1.btnExitClick(Sender: TObject);
begin
  ExitApplication;
end;

procedure TForm1.cmbMonitorChange(Sender: TObject);
begin
  if FUpdatingUI then
    Exit;
  if (FCmbMonitor = nil) or (FSettings = nil) then
    Exit;

  FSettings.LastMonitorIndex := FCmbMonitor.ItemIndex;
  if FSettings.LastMonitorIndex < 0 then
    FSettings.LastMonitorIndex := 0;
  FSettings.Save;
end;

{ ------------------------------------------------------------------ }
{ Функции уровня модуля                                              }
{ ------------------------------------------------------------------ }

function QSAppCaptureRegion: Boolean;
begin
  if Form1 <> nil then
    Result := Form1.CaptureRegion
  else
    Result := False;
end;

function QSAppCaptureWindow: Boolean;
begin
  if Form1 <> nil then
    Result := Form1.CaptureActiveWindow
  else
    Result := False;
end;

function QSAppCaptureDesktop: Boolean;
begin
  if Form1 <> nil then
    Result := Form1.CaptureDesktop
  else
    Result := False;
end;

function QSAppCaptureMonitor(AIndex: Integer): Boolean;
begin
  if Form1 <> nil then
    Result := Form1.CaptureMonitor(AIndex)
  else
    Result := False;
end;

procedure QSAppEditLast;
begin
  if Form1 <> nil then
    Form1.EditLast;
end;

function QSAppCopyLast: Boolean;
begin
  if Form1 <> nil then
    Result := Form1.CopyLast
  else
    Result := False;
end;

function QSAppSaveLast: Boolean;
begin
  if Form1 <> nil then
    Result := Form1.SaveLast
  else
    Result := False;
end;

procedure QSAppShowMainWindow;
begin
  if Form1 <> nil then
    Form1.ShowMainWindow;
end;

procedure QSAppShowSettings;
begin
  if Form1 <> nil then
    Form1.ShowSettings;
end;

procedure QSAppHideToTray;
begin
  if Form1 <> nil then
    Form1.HideToTray;
end;

procedure QSAppExit;
begin
  if Form1 <> nil then
    Form1.ExitApplication;
end;

end.
