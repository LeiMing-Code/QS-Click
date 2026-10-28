unit u_qs_editor;

{
  QS Click - визуальный редактор снимков.

  Окно редактора создаётся программно (без .fmx-ресурса) и всегда находится
  поверх остальных окон (TFormStyle.StayOnTop).

  Возможности:
    * линия или стрелка (опция "Наконечник стрелки"): первая точка -
      начало, вторая - конец. Линия заканчивается у основания наконечника,
      чтобы не выглядеть отрезком поверх треугольника;
    * маркер: широкая полупрозрачная линия с настраиваемыми цветом,
      прозрачностью и толщиной;
    * текст (цвет и размер настраиваются, опционально фон и рамка, а также
      отступ текста от краёв рамки);
    * прямоугольник и эллипс с настраиваемым контуром, толщиной,
      цветом и прозрачностью заливки;
    * размытие выделенной области;
    * масштабирование изображения колесом мыши (вверх - приблизить,
      вниз - отдалить), кнопками масштаба в статусной строке и прокрутка
      средней кнопкой мыши, когда снимок больше окна;
    * отмена и повтор (до 20 шагов);
    * копирование в буфер обмена и сохранение в PNG/JPEG;
    * горячие клавиши Ctrl+Z, Ctrl+Y, Ctrl+S, Ctrl+C, Esc.

  Курсор мыши в снимок не попадает: редактор работает с уже готовым TBitmap.
}

{$WARN SYMBOL_PLATFORM OFF}

interface

uses
  System.SysUtils,
  System.Types,
  System.UITypes,
  System.Classes,
  System.Math,
  System.Math.Vectors,
  System.Generics.Collections,
  System.IOUtils,
  Winapi.Windows,
  { ВАЖНО: Winapi.Windows объявляет TBitmap = tagBITMAP,
    поэтому FMX.Graphics должен идти после него. }
  FMX.Types,
  FMX.Controls,
  FMX.Forms,
  FMX.Graphics,
  FMX.Dialogs,
  FMX.StdCtrls,
  FMX.Objects,
  FMX.Edit,
  FMX.Colors,
  u_qs_capture,
  u_qs_settings;

type
  TQSEditorTool = (etLine, etText, etRectangle, etEllipse, etMarker, etBlur,
    etCrop, etNumber);

  TQSEditorForm = class(TForm)
  private
    FBitmap: TBitmap;
    FDefaultFileName: string;
    FTool: TQSEditorTool;

    FPenColor: TAlphaColor;
    FFillColor: TAlphaColor;
    FMarkerColor: TAlphaColor;
    FPenWidth: Integer;
    FFillOpacity: Integer;
    FTextSize: Integer;
    FTextFill: Boolean;
    FTextBorder: Boolean;
    FTextBorderWidth: Integer;
    FTextPadding: Integer;
    FArrowHead: Boolean;
    FMarkerOpacity: Integer;
    FMarkerPenWidth: Integer;
    FMarkerRoundCap: Boolean;

    { Параметры инструмента «Нумератор»: фигура с порядковым номером. }
    FNumFillColor: TAlphaColor;
    FNumTextColor: TAlphaColor;
    FNumSize: Integer;
    FNumSquare: Boolean;
    FNumCounter: Integer;

    { Масштаб и прокрутка изображения в окне редактирования. }
    FZoom: Single;
    FOffset: TPointF;
    FPanning: Boolean;
    FPanStartMouse: TPointF;
    FPanStartOffset: TPointF;

    { Новый снимок нужно вписать в окно при первой раскладке. }
    FFitOnLoad: Boolean;

    FUndo: TList<TBitmap>;
    FRedo: TList<TBitmap>;

    FToolbar: TPanel;
    FStatusPanel: TPanel;
    FPropsPanel: TPanel;
    FPaintBox: TPaintBox;
    FStatusLabel: TLabel;
    FTextEdit: TEdit;
    FChkTextFill: TCheckBox;
    FChkTextBorder: TCheckBox;
    FChkArrowHead: TCheckBox;
    FTextPaddingTrack: TTrackBar;
    FTextPaddingValue: TLabel;
    FTextBorderWidthTrack: TTrackBar;
    FTextBorderWidthValue: TLabel;
    FStrokeCombo: TComboColorBox;
    FFillCombo: TComboColorBox;
    FPenTrack: TTrackBar;
    FOpacityTrack: TTrackBar;
    FTextSizeTrack: TTrackBar;
    FPenValue: TLabel;
    FOpacityValue: TLabel;
    FTextSizeValue: TLabel;
    FToolButtons: array[TQSEditorTool] of TSpeedButton;

    { Правая панель свойств: по одной группе на инструмент. }
    FPropGroups: array[TQSEditorTool] of TGroupBox;
    FMarkerCombo: TComboColorBox;
    FMarkerPenTrack: TTrackBar;
    FMarkerPenValue: TLabel;
    FMarkerOpacityTrack: TTrackBar;
    FMarkerOpacityValue: TLabel;
    FChkMarkerRoundCap: TCheckBox;
    FNumFillCombo: TComboColorBox;
    FNumTextCombo: TComboColorBox;
    FNumSizeTrack: TTrackBar;
    FNumSizeValue: TLabel;
    FChkNumSquare: TCheckBox;

    { Кнопки масштаба в статусной строке. }
    FZoomPanel: TPanel;
    FBtnZoomOut: TButton;
    FBtnZoomIn: TButton;
    FBtnZoomReset: TButton;
    FZoomLabel: TLabel;

    FDragging: Boolean;
    FStartPoint: TPointF;
    FCurrentPoint: TPointF;

    procedure BuildUI;
    function NewLabel(AParent: TFmxObject; const AText: string;
      AX, AY, AWidth: Single): TLabel;
    function NewButton(AParent: TFmxObject; const AText: string;
      AX, AY, AWidth, AHeight: Single; AOnClick: TNotifyEvent): TButton;
    function NewToolButton(const AText: string; AX, AY, AWidth: Single;
      ATool: TQSEditorTool): TSpeedButton;
    function NewTrackBar(AParent: TFmxObject; AX, AY, AWidth: Single;
      AMin, AMax, AValue: Integer): TTrackBar;
    function NewPropGroup(const ATitle: string; AHeight: Single): TGroupBox;

    procedure SetTool(ATool: TQSEditorTool);
    procedure ShowGroupForTool(ATool: TQSEditorTool);
    procedure ToolButtonClick(Sender: TObject);
    procedure StrokeColorChange(Sender: TObject);
    procedure FillColorChange(Sender: TObject);
    procedure MarkerColorChange(Sender: TObject);
    procedure PenWidthChange(Sender: TObject);
    procedure FillOpacityChange(Sender: TObject);
    procedure TextSizeChange(Sender: TObject);
    procedure TextEditChange(Sender: TObject);
    procedure TextFillChange(Sender: TObject);
    procedure TextBorderChange(Sender: TObject);
    procedure TextBorderWidthChange(Sender: TObject);
    procedure TextPaddingChange(Sender: TObject);
    procedure MarkerOpacityChange(Sender: TObject);
    procedure MarkerPenWidthChange(Sender: TObject);
    procedure MarkerRoundCapChange(Sender: TObject);
    procedure NumFillChange(Sender: TObject);
    procedure NumTextChange(Sender: TObject);
    procedure NumSizeChange(Sender: TObject);
    procedure NumSquareChange(Sender: TObject);
    procedure ArrowHeadChange(Sender: TObject);
    procedure EditorKeyDown(Sender: TObject; var Key: Word;
      var KeyChar: WideChar; Shift: TShiftState);

    procedure PaintBoxPaint(Sender: TObject; Canvas: TCanvas);
    procedure PaintBoxMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure PaintBoxMouseMove(Sender: TObject; Shift: TShiftState;
      X, Y: Single);
    procedure PaintBoxMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure PaintBoxMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; var Handled: Boolean);
    procedure PaintBoxResize(Sender: TObject);

    function GetDestRect: TRectF;
    function ScreenToImage(const APoint: TPointF): TPointF;
    function NormalizedDragRect: TRectF;
    function ImageRectToDest(const AImageRect, ADestRect: TRectF): TRectF;
    function ImagePointToDest(const APoint: TPointF;
      const ADestRect: TRectF): TPointF;
    procedure SetZoom(ANewZoom: Single; AAnchor: TPointF);
    procedure FitZoomToWindow;
    procedure ClampZoomOffset;
    procedure UpdateZoomLabel;
    procedure DrawPreview(ACanvas: TCanvas; const ADestRect: TRectF);

    procedure PushUndo;
    procedure ClearRedo;
    procedure ClearHistory;
    procedure DoUndo;
    procedure DoRedo;

    procedure DrawRectangleOnBitmap(const R: TRectF);
    procedure DrawEllipseOnBitmap(const R: TRectF);
    procedure DrawTextOnBitmap(const R: TRectF);
    procedure DrawArrowOnBitmap(const AStart, AEnd: TPointF);
    procedure DrawMarkerOnBitmap(const AStart, AEnd: TPointF);
    procedure DrawNumberMarkerOnBitmap(const ACenter: TPointF;
      ANumber: Integer);
    function InsetTextRect(const R: TRectF; APadding: Single): TRectF;
    function ArrowBasePoint(const AStart, AEnd: TPointF;
      AHeadLen: Single): TPointF;
    procedure CommitShape;

    function CropSelected(const R: TRectF): Boolean;

    procedure BtnUndoClick(Sender: TObject);
    procedure BtnRedoClick(Sender: TObject);
    procedure BtnCopyClick(Sender: TObject);
    procedure BtnSaveClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure BtnZoomInClick(Sender: TObject);
    procedure BtnZoomOutClick(Sender: TObject);
    procedure BtnZoomResetClick(Sender: TObject);

    procedure DoCopy;
    procedure DoSave;
    procedure UpdateStatus(const AText: string);
    procedure UpdateCaption;
    procedure UpdateValueLabels;
    procedure FormCloseHandler(Sender: TObject; var Action: TCloseAction);

    { Параметры редактора: восстановление из настроек пользователя и
      синхронизация текущих значений в общий объект настроек. }
    procedure LoadEditorSettings;
    procedure SyncEditorSettings;
    procedure FormShowHandler(Sender: TObject);
  public
    constructor CreateNew(AOwner: TComponent; Dummy: NativeInt = 0); override;
    destructor Destroy; override;

    /// <summary>Загружает снимок (копирует его) и сбрасывает историю.</summary>
    procedure LoadBitmap(ABitmap: TBitmap; const ADefaultFileName: string);
  end;

/// <summary>
/// Открывает (или переиспользует) окно редактора с копией ABitmap.
/// Исходный TBitmap остаётся собственностью вызывающего кода.
/// </summary>
function QSShowEditor(ABitmap: TBitmap;
  const ADefaultFileName: string = ''): TQSEditorForm;

/// <summary>Текущее окно редактора или nil.</summary>
function QSActiveEditor: TQSEditorForm;

/// <summary>Закрывает окно редактора (объект остаётся для повторного показа).</summary>
procedure QSCloseEditor;

implementation

var
  GQSEditor: TQSEditorForm = nil;

const
  QSEditorMaxUndo = 20;
  QSDefaultPenColor: TAlphaColor = $FFFF3B30; { красный }
  QSDefaultFillColor: TAlphaColor = $FF007AFF; { синий }
  QSDefaultMarkerColor: TAlphaColor = $FFFFD600; { жёлтый маркер }
  QSDefaultPenWidth = 3;
  QSDefaultFillOpacity = 35;
  QSDefaultTextSize = 24;
  QSDefaultTextPadding = 8;
  QSDefaultTextBorderWidth = 3;
  QSDefaultMarkerOpacity = 35;
  QSDefaultMarkerPenWidth = 24;
  QSDefaultNumFillColor: TAlphaColor = $FFFF3B30; { красный круг }
  QSDefaultNumTextColor: TAlphaColor = $FFFFFFFF; { белые цифры }
  QSDefaultNumSize = 36; { диаметр круга / сторона квадрата }

  { Масштаб: минимум 10%, максимум 800%, шаг колесика/кнопок - 25%. }
  QSZoomMin = 0.1;
  QSZoomMax = 8.0;
  QSZoomStep = 1.25;
  QSPropsPanelWidth = 300;

{ ------------------------------------------------------------------ }
{ Создание и загрузка                                                }
{ ------------------------------------------------------------------ }

constructor TQSEditorForm.CreateNew(AOwner: TComponent; Dummy: NativeInt);
begin
  inherited CreateNew(AOwner, Dummy);

  FBitmap := TBitmap.Create;
  FUndo := TList<TBitmap>.Create;
  FRedo := TList<TBitmap>.Create;
  FTool := etLine;
  FPenColor := QSDefaultPenColor;
  FFillColor := QSDefaultFillColor;
  FMarkerColor := QSDefaultMarkerColor;
  FPenWidth := QSDefaultPenWidth;
  FFillOpacity := QSDefaultFillOpacity;
  FTextSize := QSDefaultTextSize;
  FTextFill := False;
  FTextBorder := False;
  FTextPadding := QSDefaultTextPadding;
  FArrowHead := False;
  FMarkerOpacity := QSDefaultMarkerOpacity;
  FMarkerPenWidth := QSDefaultMarkerPenWidth;
  FMarkerRoundCap := False;
  FNumFillColor := QSDefaultNumFillColor;
  FNumTextColor := QSDefaultNumTextColor;
  FNumSize := QSDefaultNumSize;
  FNumSquare := False;
  FNumCounter := 0;
  FTextBorderWidth := QSDefaultTextBorderWidth;
  FZoom := 1;
  FOffset := PointF(0, 0);
  FPanning := False;
  FDefaultFileName := '';

  { Последние параметры редактора из settings.ini (накладываются поверх
    значений по умолчанию, заданных выше). }
  LoadEditorSettings;

  BuildUI;
end;

destructor TQSEditorForm.Destroy;
begin
  if GQSEditor = Self then
    GQSEditor := nil;
  ClearHistory;
  FUndo.Free;
  FRedo.Free;
  FBitmap.Free;
  inherited Destroy;
end;

procedure TQSEditorForm.BuildUI;
var
  Lbl: TLabel;
  Grp: TGroupBox;
  W, H: Single;
begin
  Name := 'QSEditorForm';
  Caption := 'QS Click - редактор';
  BorderStyle := TFmxFormBorderStyle.Sizeable;
  FormStyle := TFormStyle.StayOnTop;
  Position := TFormPosition.ScreenCenter;

  W := 1240;
  H := 820;
  if Screen <> nil then
  begin
    W := Screen.WorkAreaRect.Width - 60;
    H := Screen.WorkAreaRect.Height - 60;
    if W > 1240 then
      W := 1240;
    if W < 1180 then
      W := 1180;
    if H > 820 then
      H := 820;
    if H < 600 then
      H := 600;
  end;
  { У TForm свойства Width/Height целочисленные, а WorkAreaRect
    возвращает TRectF, поэтому размеры округляем. }
  Width := Round(W);
  Height := Round(H);
  Constraints.MinWidth := 1180;
  Constraints.MinHeight := 560;

  OnKeyDown := EditorKeyDown;
  OnClose := FormCloseHandler;
  OnShow := FormShowHandler;

  FToolbar := TPanel.Create(Self);
  FToolbar.Parent := Self;
  FToolbar.Align := TAlignLayout.Top;
  FToolbar.Height := 48;

  FStatusPanel := TPanel.Create(Self);
  FStatusPanel.Parent := Self;
  FStatusPanel.Align := TAlignLayout.Bottom;
  FStatusPanel.Height := 32;

  { Панель свойств активного инструмента - справа. }
  FPropsPanel := TPanel.Create(Self);
  FPropsPanel.Parent := Self;
  FPropsPanel.Align := TAlignLayout.Right;
  FPropsPanel.Width := QSPropsPanelWidth;

  FPaintBox := TPaintBox.Create(Self);
  FPaintBox.Parent := Self;
  FPaintBox.Align := TAlignLayout.Client;
  FPaintBox.CanFocus := True;
  FPaintBox.TabStop := True;
  FPaintBox.Cursor := crCross;
  FPaintBox.OnPaint := PaintBoxPaint;
  FPaintBox.OnMouseDown := PaintBoxMouseDown;
  FPaintBox.OnMouseMove := PaintBoxMouseMove;
  FPaintBox.OnMouseUp := PaintBoxMouseUp;
  FPaintBox.OnKeyDown := EditorKeyDown;
  FPaintBox.OnMouseWheel := PaintBoxMouseWheel;
  FPaintBox.OnResize := PaintBoxResize;

  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Parent := FStatusPanel;
  FStatusLabel.Align := TAlignLayout.Client;
  FStatusLabel.TextAlign := TTextAlign.Leading;
  FStatusLabel.VertTextAlign := TTextAlign.Center;
  FStatusLabel.Padding.Left := 8;
  FStatusLabel.Margins.Left := 8;
  FStatusLabel.Text := 'Готово. Ctrl+Z/Ctrl+Y - отмена/повтор, Ctrl+S - сохранить, ' +
    'Ctrl+C - копировать, Esc - закрыть.';

  { ---------- Масштаб: панель с кнопками в статусной строке справа ---------- }
  { Панель фиксированной ширины пристыкована справа; кнопки внутри лежат
    на абсолютных координатах, поэтому порядок [−] [56%] [+] [1:1] точен. }
  FZoomPanel := TPanel.Create(Self);
  FZoomPanel.Parent := FStatusPanel;
  FZoomPanel.Align := TAlignLayout.Right;
  FZoomPanel.Width := 185;

  FBtnZoomOut := NewButton(FZoomPanel, '−', 3, 5, 28, 22, BtnZoomOutClick);
  FZoomLabel := TLabel.Create(Self);
  FZoomLabel.Parent := FZoomPanel;
  FZoomLabel.SetBounds(37, 7, 56, 18);
  FZoomLabel.TextAlign := TTextAlign.Center;
  FZoomLabel.VertTextAlign := TTextAlign.Center;
  FZoomLabel.Text := '100%';
  FBtnZoomIn := NewButton(FZoomPanel, '+', 93, 5, 28, 22, BtnZoomInClick);
  FBtnZoomReset := NewButton(FZoomPanel, '1:1', 127, 5, 52, 22, BtnZoomResetClick);

  { ---------- Инструменты (сверху) ---------- }
  { Условные иконки в названиях: → T ▭ ◯ ▮ ≈ }
  FToolButtons[etLine] := NewToolButton('→ Линия', 8, 8, 70, etLine);
  FToolButtons[etText] := NewToolButton('T Текст', 84, 8, 70, etText);
  FToolButtons[etRectangle] := NewToolButton('▭ Прямоугольник', 160, 8, 128, etRectangle);
  FToolButtons[etEllipse] := NewToolButton('◯ Эллипс', 294, 8, 72, etEllipse);
  FToolButtons[etMarker] := NewToolButton('▮ Маркер', 372, 8, 80, etMarker);
  FToolButtons[etBlur] := NewToolButton('≈ Размытие', 458, 8, 86, etBlur);
  FToolButtons[etCrop] := NewToolButton('✂ Обрезать', 550, 8, 88, etCrop);
  FToolButtons[etNumber] := NewToolButton('№ Нумератор', 644, 8, 98, etNumber);

  { ---------- Действия (сверху, справа от инструментов) ---------- }
  NewButton(FToolbar, 'Отменить', 748, 8, 68, 32, BtnUndoClick);
  NewButton(FToolbar, 'Повторить', 822, 8, 76, 32, BtnRedoClick);
  NewButton(FToolbar, 'Копировать', 906, 8, 86, 32, BtnCopyClick);
  NewButton(FToolbar, 'Сохранить', 998, 8, 86, 32, BtnSaveClick);
  NewButton(FToolbar, 'Закрыть', 1090, 8, 66, 32, BtnCloseClick);

  { ---------- Правая панель: свойства активного инструмента ---------- }
  { Общие контролы (цвет контура, толщина, заливка, прозрачность) создаются
    один раз и при переключении инструмента переносятся в нужную группу. }

  { Линия }
  Grp := NewPropGroup('Линия', 144);
  FPropGroups[etLine] := Grp;
  FChkArrowHead := TCheckBox.Create(Self);
  FChkArrowHead.Parent := Grp;
  FChkArrowHead.SetBounds(8, 26, 172, 24);
  FChkArrowHead.Text := 'Наконечник стрелки';
  FChkArrowHead.IsChecked := FArrowHead;
  FChkArrowHead.OnChange := ArrowHeadChange;
  Lbl := NewLabel(Grp, 'Цвет', 8, 58, 44);
  FStrokeCombo := TComboColorBox.Create(Self);
  FStrokeCombo.Parent := FPropsPanel;
  FStrokeCombo.Position.X := 56;
  FStrokeCombo.Position.Y := 56;
  FStrokeCombo.Width := 100;
  FStrokeCombo.Height := 26;
  FStrokeCombo.Color := FPenColor;
  FStrokeCombo.OnChange := StrokeColorChange;
  Lbl := NewLabel(Grp, 'Толщина', 8, 90, 52);
  FPenTrack := NewTrackBar(FPropsPanel, 64, 88, 150, 1, 20, FPenWidth);
  FPenTrack.OnChange := PenWidthChange;
  FPenValue := NewLabel(FPropsPanel, IntToStr(FPenWidth), 220, 90, 28);

  { Маркер }
  Grp := NewPropGroup('Маркер', 172);
  FPropGroups[etMarker] := Grp;
  Lbl := NewLabel(Grp, 'Цвет', 8, 26, 44);
  FMarkerCombo := TComboColorBox.Create(Self);
  FMarkerCombo.Parent := Grp;
  FMarkerCombo.Position.X := 56;
  FMarkerCombo.Position.Y := 24;
  FMarkerCombo.Width := 100;
  FMarkerCombo.Height := 26;
  FMarkerCombo.Color := FMarkerColor;
  FMarkerCombo.OnChange := MarkerColorChange;
  Lbl := NewLabel(Grp, 'Прозрачность', 8, 58, 90);
  FMarkerOpacityTrack := NewTrackBar(Grp, 104, 56, 140, 0, 100, FMarkerOpacity);
  FMarkerOpacityTrack.OnChange := MarkerOpacityChange;
  FMarkerOpacityValue := NewLabel(Grp, IntToStr(FMarkerOpacity), 250, 58, 28);
  Lbl := NewLabel(Grp, 'Толщина', 8, 90, 52);
  FMarkerPenTrack := NewTrackBar(Grp, 64, 88, 150, 4, 80, FMarkerPenWidth);
  FMarkerPenTrack.OnChange := MarkerPenWidthChange;
  FMarkerPenValue := NewLabel(Grp, IntToStr(FMarkerPenWidth), 220, 90, 28);
  { По умолчанию концы маркера прямые (прямоугольник); флажок даёт
    скруглённые, как у кисти. }
  FChkMarkerRoundCap := TCheckBox.Create(Self);
  FChkMarkerRoundCap.Parent := Grp;
  FChkMarkerRoundCap.SetBounds(8, 122, 170, 24);
  FChkMarkerRoundCap.Text := 'Скруглённые концы';
  FChkMarkerRoundCap.IsChecked := FMarkerRoundCap;
  FChkMarkerRoundCap.OnChange := MarkerRoundCapChange;

  { Текст }
  Grp := NewPropGroup('Текст', 292);
  FPropGroups[etText] := Grp;
  FTextEdit := TEdit.Create(Self);
  FTextEdit.Parent := Grp;
  FTextEdit.Position.X := 8;
  FTextEdit.Position.Y := 26;
  FTextEdit.Width := 268;
  FTextEdit.Height := 28;
  FTextEdit.TextPrompt := 'Текст подписи (введите здесь)';
  FTextEdit.Text := '';
  FTextEdit.OnChange := TextEditChange;
  Lbl := NewLabel(Grp, 'Размер', 8, 62, 44);
  FTextSizeTrack := NewTrackBar(Grp, 56, 60, 150, 10, 72, FTextSize);
  FTextSizeTrack.OnChange := TextSizeChange;
  FTextSizeValue := NewLabel(Grp, IntToStr(FTextSize), 212, 62, 28);
  Lbl := NewLabel(Grp, 'Цвет текста', 8, 94, 78);
  FChkTextFill := TCheckBox.Create(Self);
  FChkTextFill.Parent := Grp;
  FChkTextFill.SetBounds(8, 124, 130, 24);
  FChkTextFill.Text := 'Фон под текстом';
  FChkTextFill.IsChecked := FTextFill;
  FChkTextFill.OnChange := TextFillChange;
  FChkTextBorder := TCheckBox.Create(Self);
  FChkTextBorder.Parent := Grp;
  FChkTextBorder.SetBounds(146, 124, 130, 24);
  FChkTextBorder.Text := 'Рамка текста';
  FChkTextBorder.IsChecked := FTextBorder;
  FChkTextBorder.OnChange := TextBorderChange;
  Lbl := NewLabel(Grp, 'Заливка', 8, 156, 44);
  Lbl := NewLabel(Grp, 'Прозрач.', 8, 188, 56);
  Lbl := NewLabel(Grp, 'Отступ', 8, 220, 44);
  FTextPaddingTrack := NewTrackBar(Grp, 56, 218, 150, 0, 48, FTextPadding);
  FTextPaddingTrack.OnChange := TextPaddingChange;
  FTextPaddingValue := NewLabel(Grp, IntToStr(FTextPadding), 212, 220, 28);
  Lbl := NewLabel(Grp, 'Толщина рамки', 8, 252, 92);
  FTextBorderWidthTrack := NewTrackBar(Grp, 104, 250, 140, 1, 20, FTextBorderWidth);
  FTextBorderWidthTrack.OnChange := TextBorderWidthChange;
  FTextBorderWidthTrack.Enabled := FTextBorder;
  FTextBorderWidthValue := NewLabel(Grp, IntToStr(FTextBorderWidth), 250, 252, 28);

  { Прямоугольник }
  Grp := NewPropGroup('Прямоугольник', 172);
  FPropGroups[etRectangle] := Grp;
  Lbl := NewLabel(Grp, 'Контур', 8, 26, 44);
  Lbl := NewLabel(Grp, 'Толщина', 8, 58, 52);
  Lbl := NewLabel(Grp, 'Заливка', 8, 88, 44);
  Lbl := NewLabel(Grp, 'Прозрач.', 8, 118, 56);
  FFillCombo := TComboColorBox.Create(Self);
  FFillCombo.Parent := Grp;
  FFillCombo.Position.X := 56;
  FFillCombo.Position.Y := 86;
  FFillCombo.Width := 100;
  FFillCombo.Height := 26;
  FFillCombo.Color := FFillColor;
  FFillCombo.OnChange := FillColorChange;
  FOpacityTrack := NewTrackBar(Grp, 66, 116, 150, 0, 100, FFillOpacity);
  FOpacityTrack.OnChange := FillOpacityChange;
  FOpacityValue := NewLabel(Grp, IntToStr(FFillOpacity), 222, 118, 28);

  { Эллипс }
  Grp := NewPropGroup('Эллипс', 172);
  FPropGroups[etEllipse] := Grp;
  Lbl := NewLabel(Grp, 'Контур', 8, 26, 44);
  Lbl := NewLabel(Grp, 'Толщина', 8, 58, 52);
  Lbl := NewLabel(Grp, 'Заливка', 8, 88, 44);
  Lbl := NewLabel(Grp, 'Прозрач.', 8, 118, 56);

  { Размытие }
  Grp := NewPropGroup('Размытие', 72);
  FPropGroups[etBlur] := Grp;
  Lbl := NewLabel(Grp, 'Выделите область мышью - она будет размыта.', 8, 26, 268);
  Lbl.Height := 40;

  { Обрезка }
  Grp := NewPropGroup('Обрезка', 72);
  FPropGroups[etCrop] := Grp;
  Lbl := NewLabel(Grp, 'Выделите область и отпустите кнопку - снимок будет обрезан.', 8, 26, 268);
  Lbl.Height := 40;

  { Нумератор }
  Grp := NewPropGroup('Нумератор', 172);
  FPropGroups[etNumber] := Grp;
  Lbl := NewLabel(Grp, 'Цвет заливки', 8, 26, 92);
  FNumFillCombo := TComboColorBox.Create(Self);
  FNumFillCombo.Parent := Grp;
  FNumFillCombo.Position.X := 104;
  FNumFillCombo.Position.Y := 24;
  FNumFillCombo.Width := 100;
  FNumFillCombo.Height := 26;
  FNumFillCombo.Color := FNumFillColor;
  FNumFillCombo.OnChange := NumFillChange;
  Lbl := NewLabel(Grp, 'Цвет цифр', 8, 58, 92);
  FNumTextCombo := TComboColorBox.Create(Self);
  FNumTextCombo.Parent := Grp;
  FNumTextCombo.Position.X := 104;
  FNumTextCombo.Position.Y := 56;
  FNumTextCombo.Width := 100;
  FNumTextCombo.Height := 26;
  FNumTextCombo.Color := FNumTextColor;
  FNumTextCombo.OnChange := NumTextChange;
  Lbl := NewLabel(Grp, 'Диаметр', 8, 90, 56);
  FNumSizeTrack := NewTrackBar(Grp, 64, 88, 150, 12, 100, FNumSize);
  FNumSizeTrack.OnChange := NumSizeChange;
  FNumSizeValue := NewLabel(Grp, IntToStr(FNumSize), 220, 90, 28);
  FChkNumSquare := TCheckBox.Create(Self);
  FChkNumSquare.Parent := Grp;
  FChkNumSquare.SetBounds(8, 124, 130, 24);
  FChkNumSquare.Text := 'Квадрат';
  FChkNumSquare.IsChecked := FNumSquare;
  FChkNumSquare.OnChange := NumSquareChange;

  SetTool(etLine);
  UpdateValueLabels;
  UpdateZoomLabel;
  UpdateCaption;
end;

function TQSEditorForm.NewLabel(AParent: TFmxObject; const AText: string;
  AX, AY, AWidth: Single): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.Position.X := AX;
  Result.Position.Y := AY;
  Result.Width := AWidth;
  Result.Height := 24;
  Result.AutoSize := False;
  Result.TextAlign := TTextAlign.Leading;
  Result.VertTextAlign := TTextAlign.Center;
  Result.Text := AText;
end;

function TQSEditorForm.NewButton(AParent: TFmxObject; const AText: string;
  AX, AY, AWidth, AHeight: Single; AOnClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Position.X := AX;
  Result.Position.Y := AY;
  Result.Width := AWidth;
  Result.Height := AHeight;
  Result.Text := AText;
  Result.OnClick := AOnClick;
end;

function TQSEditorForm.NewToolButton(const AText: string; AX, AY,
  AWidth: Single; ATool: TQSEditorTool): TSpeedButton;
begin
  Result := TSpeedButton.Create(Self);
  Result.Parent := FToolbar;
  Result.Position.X := AX;
  Result.Position.Y := AY;
  Result.Width := AWidth;
  Result.Height := 32;
  Result.Text := AText;
  Result.Tag := Ord(ATool);
  Result.GroupName := 'QSEditorTools';
  Result.StaysPressed := True;
  Result.OnClick := ToolButtonClick;
end;

function TQSEditorForm.NewTrackBar(AParent: TFmxObject; AX, AY,
  AWidth: Single; AMin, AMax, AValue: Integer): TTrackBar;
begin
  Result := TTrackBar.Create(Self);
  Result.Parent := AParent;
  Result.Position.X := AX;
  Result.Position.Y := AY;
  Result.Width := AWidth;
  Result.Height := 24;
  Result.Orientation := TOrientation.Horizontal;
  Result.Min := AMin;
  Result.Max := AMax;
  Result.Value := AValue;
  Result.Frequency := 1;
end;

function TQSEditorForm.NewPropGroup(const ATitle: string;
  AHeight: Single): TGroupBox;
begin
  Result := TGroupBox.Create(Self);
  Result.Parent := FPropsPanel;
  Result.Align := TAlignLayout.Top;
  Result.Height := AHeight;
  Result.Margins.Left := 8;
  Result.Margins.Right := 8;
  Result.Margins.Top := 8;
  Result.Text := ATitle;
end;

procedure TQSEditorForm.LoadBitmap(ABitmap: TBitmap;
  const ADefaultFileName: string);
begin
  if (ABitmap = nil) or ABitmap.IsEmpty then
    Exit;

  QSCopyBitmap(ABitmap, FBitmap);
  FDefaultFileName := ADefaultFileName;
  ClearHistory;
  { Нумератор начинает новый счёт с 1 на каждом снимке. }
  FNumCounter := 0;
  { Новый снимок вписывается в область рисования целиком: если раскладка
    окна уже готова, масштаб подбирается сразу, иначе - при первом Resize. }
  FFitOnLoad := True;
  FitZoomToWindow;
  UpdateZoomLabel;
  UpdateCaption;
  UpdateStatus('Снимок загружен. Выберите инструмент и работайте с изображением.');
  if FPaintBox <> nil then
    FPaintBox.Repaint;
end;

function QSShowEditor(ABitmap: TBitmap;
  const ADefaultFileName: string): TQSEditorForm;
begin
  Result := nil;
  if (ABitmap = nil) or ABitmap.IsEmpty then
    Exit;

  if GQSEditor = nil then
    GQSEditor := TQSEditorForm.CreateNew(Application);

  GQSEditor.LoadBitmap(ABitmap, ADefaultFileName);
  if GQSEditor.WindowState = TWindowState.wsMinimized then
    GQSEditor.WindowState := TWindowState.wsNormal;
  GQSEditor.Show;
  GQSEditor.BringToFront;
  { Принудительная перерисовка сразу после показа: без неё на Windows
    часть контролов до первого клика/наведения остаётся непрорисованной. }
  GQSEditor.Invalidate;
  Result := GQSEditor;
end;

function QSActiveEditor: TQSEditorForm;
begin
  Result := GQSEditor;
end;

procedure QSCloseEditor;
begin
  if GQSEditor <> nil then
    GQSEditor.Close;
end;

{ ------------------------------------------------------------------ }
{ Инструменты и параметры                                            }
{ ------------------------------------------------------------------ }

procedure TQSEditorForm.SetTool(ATool: TQSEditorTool);
var
  T: TQSEditorTool;
begin
  FTool := ATool;
  for T := Low(TQSEditorTool) to High(TQSEditorTool) do
    if FToolButtons[T] <> nil then
      FToolButtons[T].IsPressed := T = ATool;

  ShowGroupForTool(ATool);

  if FPaintBox <> nil then
    FPaintBox.Cursor := crCross;

  case ATool of
    etLine:
      if FArrowHead then
        UpdateStatus('Стрелка: протяните мышью от начала к концу отрезка.')
      else
        UpdateStatus('Линия: протяните мышью от начала к концу отрезка.');
    etText: UpdateStatus('Текст: введите подпись и протяните область (можно включить фон, рамку и отступ).');
    etRectangle: UpdateStatus('Прямоугольник: протяните мышью нужную область.');
    etEllipse: UpdateStatus('Эллипс: протяните мышью нужную область.');
    etMarker: UpdateStatus('Маркер: протяните мышью, рисуя широкую полупрозрачную линию.');
    etBlur: UpdateStatus('Размытие: протяните мышью область, которую нужно размыть.');
    etCrop: UpdateStatus('Обрезка: выделите область, которая останется на снимке.');
    etNumber: UpdateStatus('Нумератор: кликните мышью в точку, где поставить номер.');
  end;
end;

procedure TQSEditorForm.ShowGroupForTool(ATool: TQSEditorTool);
var
  T: TQSEditorTool;
  G: TGroupBox;
begin
  { Видна только группа свойств активного инструмента. }
  for T := Low(TQSEditorTool) to High(TQSEditorTool) do
    if FPropGroups[T] <> nil then
      FPropGroups[T].Visible := (T = ATool);

  G := FPropGroups[ATool];
  if G = nil then
    Exit;

  { Общие параметры (контур/цвет, толщина, заливка, прозрачность)
    переносятся в группу активного инструмента. Повторный перенос
    одинаковых контролов отбрасывается, чтобы не сбивать координаты. }
  case ATool of
    etLine:
      begin
        if FStrokeCombo.Parent <> G then
          FStrokeCombo.Parent := G;
        FStrokeCombo.Position.X := 56;
        FStrokeCombo.Position.Y := 56;
        if FPenTrack.Parent <> G then
          FPenTrack.Parent := G;
        FPenTrack.Position.X := 64;
        FPenTrack.Position.Y := 88;
        if FPenValue.Parent <> G then
          FPenValue.Parent := G;
        FPenValue.Position.X := 220;
        FPenValue.Position.Y := 90;
        FStrokeCombo.Color := FPenColor;
        FPenTrack.Value := FPenWidth;
      end;

    etRectangle, etEllipse:
      begin
        if FStrokeCombo.Parent <> G then
          FStrokeCombo.Parent := G;
        FStrokeCombo.Position.X := 56;
        FStrokeCombo.Position.Y := 24;
        if FPenTrack.Parent <> G then
          FPenTrack.Parent := G;
        FPenTrack.Position.X := 64;
        FPenTrack.Position.Y := 56;
        if FPenValue.Parent <> G then
          FPenValue.Parent := G;
        FPenValue.Position.X := 220;
        FPenValue.Position.Y := 58;
        if FFillCombo.Parent <> G then
          FFillCombo.Parent := G;
        FFillCombo.Position.X := 56;
        FFillCombo.Position.Y := 86;
        if FOpacityTrack.Parent <> G then
          FOpacityTrack.Parent := G;
        FOpacityTrack.Position.X := 66;
        FOpacityTrack.Position.Y := 116;
        if FOpacityValue.Parent <> G then
          FOpacityValue.Parent := G;
        FOpacityValue.Position.X := 222;
        FOpacityValue.Position.Y := 118;
        FStrokeCombo.Color := FPenColor;
        FPenTrack.Value := FPenWidth;
        FFillCombo.Color := FFillColor;
        FOpacityTrack.Value := FFillOpacity;
      end;

    etText:
      begin
        if FStrokeCombo.Parent <> G then
          FStrokeCombo.Parent := G;
        FStrokeCombo.Position.X := 88;
        FStrokeCombo.Position.Y := 92;
        if FFillCombo.Parent <> G then
          FFillCombo.Parent := G;
        FFillCombo.Position.X := 56;
        FFillCombo.Position.Y := 154;
        if FOpacityTrack.Parent <> G then
          FOpacityTrack.Parent := G;
        FOpacityTrack.Position.X := 104;
        FOpacityTrack.Position.Y := 186;
        if FOpacityValue.Parent <> G then
          FOpacityValue.Parent := G;
        FOpacityValue.Position.X := 250;
        FOpacityValue.Position.Y := 188;
        FStrokeCombo.Color := FPenColor;
        FFillCombo.Color := FFillColor;
        FOpacityTrack.Value := FFillOpacity;
      end;

    { etCrop: общая панель с подсказкой, переносить нечего. }
  end;
end;

procedure TQSEditorForm.ToolButtonClick(Sender: TObject);
begin
  if Sender is TSpeedButton then
    SetTool(TQSEditorTool(TSpeedButton(Sender).Tag));
end;

procedure TQSEditorForm.StrokeColorChange(Sender: TObject);
begin
  if FStrokeCombo <> nil then
    FPenColor := FStrokeCombo.Color;
  SyncEditorSettings;
end;

procedure TQSEditorForm.FillColorChange(Sender: TObject);
begin
  if FFillCombo <> nil then
    FFillColor := FFillCombo.Color;
  SyncEditorSettings;
end;

procedure TQSEditorForm.MarkerColorChange(Sender: TObject);
begin
  if FMarkerCombo <> nil then
    FMarkerColor := FMarkerCombo.Color;
  SyncEditorSettings;
  if FDragging and (FPaintBox <> nil) then
    FPaintBox.Repaint;
end;

procedure TQSEditorForm.MarkerOpacityChange(Sender: TObject);
begin
  if FMarkerOpacityTrack <> nil then
    FMarkerOpacity := EnsureRange(Round(FMarkerOpacityTrack.Value), 0, 100);
  UpdateValueLabels;
  if FDragging and (FPaintBox <> nil) then
    FPaintBox.Repaint;
end;

procedure TQSEditorForm.MarkerPenWidthChange(Sender: TObject);
begin
  if FMarkerPenTrack <> nil then
    FMarkerPenWidth := EnsureRange(Round(FMarkerPenTrack.Value), 4, 80);
  UpdateValueLabels;
  if FDragging and (FPaintBox <> nil) then
    FPaintBox.Repaint;
end;

procedure TQSEditorForm.MarkerRoundCapChange(Sender: TObject);
begin
  if FChkMarkerRoundCap <> nil then
    FMarkerRoundCap := FChkMarkerRoundCap.IsChecked;
  SyncEditorSettings;
  if FDragging and (FPaintBox <> nil) then
    FPaintBox.Repaint;
end;

procedure TQSEditorForm.NumFillChange(Sender: TObject);
begin
  if FNumFillCombo <> nil then
    FNumFillColor := FNumFillCombo.Color;
  SyncEditorSettings;
end;

procedure TQSEditorForm.NumTextChange(Sender: TObject);
begin
  if FNumTextCombo <> nil then
    FNumTextColor := FNumTextCombo.Color;
  SyncEditorSettings;
end;

procedure TQSEditorForm.NumSizeChange(Sender: TObject);
begin
  if FNumSizeTrack <> nil then
    FNumSize := EnsureRange(Round(FNumSizeTrack.Value), 12, 100);
  UpdateValueLabels;
  if FDragging and (FPaintBox <> nil) then
    FPaintBox.Repaint;
end;

procedure TQSEditorForm.NumSquareChange(Sender: TObject);
begin
  if FChkNumSquare <> nil then
    FNumSquare := FChkNumSquare.IsChecked;
  SyncEditorSettings;
  if FDragging and (FPaintBox <> nil) then
    FPaintBox.Repaint;
end;

procedure TQSEditorForm.PenWidthChange(Sender: TObject);
begin
  if FPenTrack <> nil then
    FPenWidth := EnsureRange(Round(FPenTrack.Value), 1, 20);
  UpdateValueLabels;
end;

procedure TQSEditorForm.FillOpacityChange(Sender: TObject);
begin
  if FOpacityTrack <> nil then
    FFillOpacity := EnsureRange(Round(FOpacityTrack.Value), 0, 100);
  UpdateValueLabels;
end;

procedure TQSEditorForm.TextSizeChange(Sender: TObject);
begin
  if FTextSizeTrack <> nil then
    FTextSize := EnsureRange(Round(FTextSizeTrack.Value), 10, 72);
  UpdateValueLabels;
end;

procedure TQSEditorForm.TextEditChange(Sender: TObject);
begin
  if (FTool = etText) and (FPaintBox <> nil) then
    FPaintBox.Repaint;
end;

procedure TQSEditorForm.TextFillChange(Sender: TObject);
begin
  if FChkTextFill <> nil then
    FTextFill := FChkTextFill.IsChecked;
  SyncEditorSettings;
  if (FTool = etText) and (FPaintBox <> nil) then
    FPaintBox.Repaint;
end;

procedure TQSEditorForm.TextBorderChange(Sender: TObject);
begin
  if FChkTextBorder <> nil then
    FTextBorder := FChkTextBorder.IsChecked;
  if FTextBorderWidthTrack <> nil then
    FTextBorderWidthTrack.Enabled := FTextBorder;
  SyncEditorSettings;
  if (FTool = etText) and (FPaintBox <> nil) then
    FPaintBox.Repaint;
end;

procedure TQSEditorForm.TextBorderWidthChange(Sender: TObject);
begin
  if FTextBorderWidthTrack <> nil then
    FTextBorderWidth := EnsureRange(Round(FTextBorderWidthTrack.Value), 1, 20);
  UpdateValueLabels;
  if (FTool = etText) and (FPaintBox <> nil) then
    FPaintBox.Repaint;
end;

procedure TQSEditorForm.TextPaddingChange(Sender: TObject);
begin
  if FTextPaddingTrack <> nil then
    FTextPadding := EnsureRange(Round(FTextPaddingTrack.Value), 0, 48);
  UpdateValueLabels;
  if (FTool = etText) and (FPaintBox <> nil) then
    FPaintBox.Repaint;
end;

procedure TQSEditorForm.ArrowHeadChange(Sender: TObject);
begin
  if FChkArrowHead <> nil then
    FArrowHead := FChkArrowHead.IsChecked;
  SyncEditorSettings;

  { Инструмент не переключаем: флажок лишь меняет вид уже выбранной
    линии. Подсказку обновляем, только если линия активна. }
  if FTool = etLine then
  begin
    if FArrowHead then
      UpdateStatus('Стрелка: протяните мышью от начала к концу отрезка.')
    else
      UpdateStatus('Линия: протяните мышью от начала к концу отрезка.');
  end;

  if FDragging and (FPaintBox <> nil) then
    FPaintBox.Repaint;
end;

procedure TQSEditorForm.UpdateValueLabels;
begin
  if FPenValue <> nil then
    FPenValue.Text := IntToStr(FPenWidth);
  if FOpacityValue <> nil then
    FOpacityValue.Text := IntToStr(FFillOpacity);
  if FTextSizeValue <> nil then
    FTextSizeValue.Text := IntToStr(FTextSize);
  if FTextPaddingValue <> nil then
    FTextPaddingValue.Text := IntToStr(FTextPadding);
  if FTextBorderWidthValue <> nil then
    FTextBorderWidthValue.Text := IntToStr(FTextBorderWidth);
  if FMarkerOpacityValue <> nil then
    FMarkerOpacityValue.Text := IntToStr(FMarkerOpacity);
  if FMarkerPenValue <> nil then
    FMarkerPenValue.Text := IntToStr(FMarkerPenWidth);
  if FNumSizeValue <> nil then
    FNumSizeValue.Text := IntToStr(FNumSize);
  { Числовые параметры меняются только через эти обработчики, поэтому
    синхронизируем их с общим объектом настроек здесь: сохранение в
    settings.ini происходит и при закрытии редактора, и при выходе
    из приложения. }
  SyncEditorSettings;
end;

procedure TQSEditorForm.UpdateCaption;
begin
  if (FBitmap <> nil) and not FBitmap.IsEmpty then
    Caption := Format('QS Click - редактор [%d x %d]',
      [FBitmap.Width, FBitmap.Height])
  else
    Caption := 'QS Click - редактор';
end;

procedure TQSEditorForm.UpdateStatus(const AText: string);
begin
  if FStatusLabel <> nil then
    FStatusLabel.Text := AText;
end;

procedure TQSEditorForm.LoadEditorSettings;
begin
  if QSGlobalSettings = nil then
    Exit;
  FPenColor := QSGlobalSettings.EditorPenColor;
  FFillColor := QSGlobalSettings.EditorFillColor;
  FMarkerColor := QSGlobalSettings.EditorMarkerColor;
  FPenWidth := EnsureRange(QSGlobalSettings.EditorPenWidth, 1, 20);
  FFillOpacity := EnsureRange(QSGlobalSettings.EditorFillOpacity, 0, 100);
  FTextSize := EnsureRange(QSGlobalSettings.EditorTextSize, 10, 72);
  FTextFill := QSGlobalSettings.EditorTextFill;
  FTextBorder := QSGlobalSettings.EditorTextBorder;
  FTextBorderWidth := EnsureRange(QSGlobalSettings.EditorTextBorderWidth, 1, 20);
  FTextPadding := EnsureRange(QSGlobalSettings.EditorTextPadding, 0, 48);
  FArrowHead := QSGlobalSettings.EditorArrowHead;
  FMarkerOpacity := EnsureRange(QSGlobalSettings.EditorMarkerOpacity, 0, 100);
  FMarkerPenWidth := EnsureRange(QSGlobalSettings.EditorMarkerPenWidth, 4, 80);
  FMarkerRoundCap := QSGlobalSettings.EditorMarkerRoundCap;
  FNumFillColor := QSGlobalSettings.EditorNumFillColor;
  FNumTextColor := QSGlobalSettings.EditorNumTextColor;
  FNumSize := EnsureRange(QSGlobalSettings.EditorNumSize, 12, 100);
  FNumSquare := QSGlobalSettings.EditorNumSquare;
end;

procedure TQSEditorForm.SyncEditorSettings;
begin
  if QSGlobalSettings = nil then
    Exit;
  QSGlobalSettings.EditorPenColor := FPenColor;
  QSGlobalSettings.EditorFillColor := FFillColor;
  QSGlobalSettings.EditorMarkerColor := FMarkerColor;
  QSGlobalSettings.EditorPenWidth := FPenWidth;
  QSGlobalSettings.EditorFillOpacity := FFillOpacity;
  QSGlobalSettings.EditorTextSize := FTextSize;
  QSGlobalSettings.EditorTextFill := FTextFill;
  QSGlobalSettings.EditorTextBorder := FTextBorder;
  QSGlobalSettings.EditorTextBorderWidth := FTextBorderWidth;
  QSGlobalSettings.EditorTextPadding := FTextPadding;
  QSGlobalSettings.EditorArrowHead := FArrowHead;
  QSGlobalSettings.EditorMarkerOpacity := FMarkerOpacity;
  QSGlobalSettings.EditorMarkerPenWidth := FMarkerPenWidth;
  QSGlobalSettings.EditorMarkerRoundCap := FMarkerRoundCap;
  QSGlobalSettings.EditorNumFillColor := FNumFillColor;
  QSGlobalSettings.EditorNumTextColor := FNumTextColor;
  QSGlobalSettings.EditorNumSize := FNumSize;
  QSGlobalSettings.EditorNumSquare := FNumSquare;
end;

{ ------------------------------------------------------------------ }
{ История действий                                                   }
{ ------------------------------------------------------------------ }

procedure TQSEditorForm.ClearRedo;
var
  I: Integer;
begin
  for I := 0 to FRedo.Count - 1 do
    FRedo[I].Free;
  FRedo.Clear;
end;

procedure TQSEditorForm.ClearHistory;
var
  I: Integer;
begin
  for I := 0 to FUndo.Count - 1 do
    FUndo[I].Free;
  FUndo.Clear;
  ClearRedo;
end;

procedure TQSEditorForm.PushUndo;
var
  Snapshot: TBitmap;
begin
  Snapshot := QSCloneBitmap(FBitmap);
  if Snapshot = nil then
    Exit;

  if FUndo.Count >= QSEditorMaxUndo then
  begin
    FUndo[0].Free;
    FUndo.Delete(0);
  end;
  FUndo.Add(Snapshot);
  ClearRedo;
end;

procedure TQSEditorForm.DoUndo;
var
  Prev, Snapshot: TBitmap;
begin
  if FUndo.Count = 0 then
    Exit;

  Snapshot := QSCloneBitmap(FBitmap);
  if Snapshot <> nil then
    FRedo.Add(Snapshot);

  Prev := FUndo[FUndo.Count - 1];
  FUndo.Delete(FUndo.Count - 1);
  QSCopyBitmap(Prev, FBitmap);
  Prev.Free;

  UpdateCaption;
  UpdateStatus('Действие отменено.');
  if FPaintBox <> nil then
    FPaintBox.Repaint;
end;

procedure TQSEditorForm.DoRedo;
var
  Next, Snapshot: TBitmap;
begin
  if FRedo.Count = 0 then
    Exit;

  Snapshot := QSCloneBitmap(FBitmap);
  if Snapshot <> nil then
    FUndo.Add(Snapshot);

  Next := FRedo[FRedo.Count - 1];
  FRedo.Delete(FRedo.Count - 1);
  QSCopyBitmap(Next, FBitmap);
  Next.Free;

  UpdateCaption;
  UpdateStatus('Действие повторено.');
  if FPaintBox <> nil then
    FPaintBox.Repaint;
end;

{ ------------------------------------------------------------------ }
{ Рисование на изображении                                          }
{ ------------------------------------------------------------------ }

procedure TQSEditorForm.DrawRectangleOnBitmap(const R: TRectF);
begin
  if not FBitmap.Canvas.BeginScene then
    Exit;
  try
    FBitmap.Canvas.Stroke.Kind := TBrushKind.Solid;
    FBitmap.Canvas.Stroke.Color := FPenColor;
    FBitmap.Canvas.Stroke.Thickness := FPenWidth;
    FBitmap.Canvas.Stroke.Dash := TStrokeDash.Solid;

    FBitmap.Canvas.Fill.Kind := TBrushKind.Solid;
    FBitmap.Canvas.Fill.Color := FFillColor;
    if FFillOpacity > 0 then
      FBitmap.Canvas.FillRect(R, FFillOpacity / 100);

    FBitmap.Canvas.DrawRect(R, 1);
  finally
    FBitmap.Canvas.EndScene;
  end;
end;

procedure TQSEditorForm.DrawEllipseOnBitmap(const R: TRectF);
begin
  if not FBitmap.Canvas.BeginScene then
    Exit;
  try
    FBitmap.Canvas.Stroke.Kind := TBrushKind.Solid;
    FBitmap.Canvas.Stroke.Color := FPenColor;
    FBitmap.Canvas.Stroke.Thickness := FPenWidth;
    FBitmap.Canvas.Stroke.Dash := TStrokeDash.Solid;

    FBitmap.Canvas.Fill.Kind := TBrushKind.Solid;
    FBitmap.Canvas.Fill.Color := FFillColor;
    if FFillOpacity > 0 then
      FBitmap.Canvas.FillEllipse(R, FFillOpacity / 100);

    FBitmap.Canvas.DrawEllipse(R, 1);
  finally
    FBitmap.Canvas.EndScene;
  end;
end;

procedure TQSEditorForm.DrawTextOnBitmap(const R: TRectF);
var
  FillOp: Single;
  TR: TRectF;
begin
  if not FBitmap.Canvas.BeginScene then
    Exit;
  try
    { Фон и рамка рисуются первыми, чтобы подпись осталась поверх них. }
    if FTextFill then
    begin
      FillOp := FFillOpacity / 100;
      if FillOp < 0.05 then
        FillOp := 0.05;
      if FillOp > 1 then
        FillOp := 1;
      FBitmap.Canvas.Fill.Kind := TBrushKind.Solid;
      FBitmap.Canvas.Fill.Color := FFillColor;
      FBitmap.Canvas.FillRect(R, FillOp);
    end;

    if FTextBorder then
    begin
      FBitmap.Canvas.Stroke.Kind := TBrushKind.Solid;
      FBitmap.Canvas.Stroke.Color := FPenColor;
      FBitmap.Canvas.Stroke.Thickness := FTextBorderWidth;
      FBitmap.Canvas.Stroke.Dash := TStrokeDash.Solid;
      FBitmap.Canvas.DrawRect(R, 1);
    end;

    { Текст всегда рисуется с отступом от краёв области, чтобы не липнуть
      к фону и рамке. }
    TR := InsetTextRect(R, FTextPadding);

    FBitmap.Canvas.Fill.Kind := TBrushKind.Solid;
    FBitmap.Canvas.Fill.Color := FPenColor;
    FBitmap.Canvas.Font.Family := 'Segoe UI';
    FBitmap.Canvas.Font.Size := FTextSize;
    FBitmap.Canvas.FillText(TR, FTextEdit.Text, True, 1, [],
      TTextAlign.Leading, TTextAlign.Leading);
  finally
    FBitmap.Canvas.EndScene;
  end;
end;

function TQSEditorForm.InsetTextRect(const R: TRectF;
  APadding: Single): TRectF;
begin
  Result := R;
  if APadding <= 0 then
    Exit;
  if Result.Width > APadding * 2 then
  begin
    Result.Left := Result.Left + APadding;
    Result.Right := Result.Right - APadding;
  end;
  if Result.Height > APadding * 2 then
  begin
    Result.Top := Result.Top + APadding;
    Result.Bottom := Result.Bottom - APadding;
  end;
end;

function TQSEditorForm.ArrowBasePoint(const AStart, AEnd: TPointF;
  AHeadLen: Single): TPointF;
var
  Angle, BaseDist, Len: Single;
begin
  Result := AEnd;
  Len := Hypot(AEnd.X - AStart.X, AEnd.Y - AStart.Y);
  if Len <= 0.01 then
    Exit;

  { Расстояние от вершины наконечника до середины его основания. }
  BaseDist := AHeadLen * Cos(Pi / 7);
  if BaseDist >= Len then
    Exit(AStart);

  Angle := ArcTan2(AEnd.Y - AStart.Y, AEnd.X - AStart.X);
  Result := PointF(AEnd.X - BaseDist * Cos(Angle),
    AEnd.Y - BaseDist * Sin(Angle));
end;

procedure TQSEditorForm.DrawArrowOnBitmap(const AStart, AEnd: TPointF);
var
  HeadLen: Single;
  Angle, Base: Single;
  P1, P2, LineEnd: TPointF;
  Poly: TPolygon;
begin
  if not FBitmap.Canvas.BeginScene then
    Exit;
  try
    FBitmap.Canvas.Stroke.Kind := TBrushKind.Solid;
    FBitmap.Canvas.Stroke.Color := FPenColor;
    FBitmap.Canvas.Stroke.Thickness := FPenWidth;
    FBitmap.Canvas.Stroke.Dash := TStrokeDash.Solid;

    HeadLen := Max(10, FPenWidth * 4);

    if FArrowHead then
      { Отрезок заканчивается у основания наконечника, а не в его вершине,
        иначе линия выглядит продолжением за стрелкой. }
      LineEnd := ArrowBasePoint(AStart, AEnd, HeadLen)
    else
      LineEnd := AEnd;

    FBitmap.Canvas.DrawLine(AStart, LineEnd, 1);

    if not FArrowHead then
      Exit;

    { Наконечник-треугольник в конечной точке; размер зависит от толщины. }
    Angle := ArcTan2(AEnd.Y - AStart.Y, AEnd.X - AStart.X);
    Base := Angle + Pi;
    P1 := PointF(AEnd.X + HeadLen * Cos(Base + Pi / 7),
      AEnd.Y + HeadLen * Sin(Base + Pi / 7));
    P2 := PointF(AEnd.X + HeadLen * Cos(Base - Pi / 7),
      AEnd.Y + HeadLen * Sin(Base - Pi / 7));

    SetLength(Poly, 3);
    Poly[0] := AEnd;
    Poly[1] := P1;
    Poly[2] := P2;

    FBitmap.Canvas.Fill.Kind := TBrushKind.Solid;
    FBitmap.Canvas.Fill.Color := FPenColor;
    FBitmap.Canvas.FillPolygon(Poly, 1);
  finally
    FBitmap.Canvas.EndScene;
  end;
end;

procedure TQSEditorForm.DrawMarkerOnBitmap(const AStart, AEnd: TPointF);
begin
  if not FBitmap.Canvas.BeginScene then
    Exit;
  try
    { Цвет маркера с прозрачностью: альфа складывается с его цветом. }
    FBitmap.Canvas.Stroke.Kind := TBrushKind.Solid;
    FBitmap.Canvas.Stroke.Color := (FMarkerColor and $00FFFFFF) or
      (TAlphaColor(Round(FMarkerOpacity * 2.55)) shl 24);
    FBitmap.Canvas.Stroke.Thickness := FMarkerPenWidth;
    { По умолчанию концы прямые (прямоугольный маркер); скругление
      включается флажком «Скруглённые концы». }
    if FMarkerRoundCap then
      FBitmap.Canvas.Stroke.Cap := TStrokeCap.Round
    else
      FBitmap.Canvas.Stroke.Cap := TStrokeCap.Flat;
    FBitmap.Canvas.Stroke.Dash := TStrokeDash.Solid;
    FBitmap.Canvas.DrawLine(AStart, AEnd, 1);
  finally
    FBitmap.Canvas.EndScene;
  end;
end;

procedure TQSEditorForm.DrawNumberMarkerOnBitmap(const ACenter: TPointF;
  ANumber: Integer);
var
  D, MaxW: Single;
  R: TRectF;
  S: string;
begin
  if not FBitmap.Canvas.BeginScene then
    Exit;
  try
    D := FNumSize;
    R := RectF(ACenter.X - D / 2, ACenter.Y - D / 2,
      ACenter.X + D / 2, ACenter.Y + D / 2);

    { Круг или квадрат, всегда без рамки. }
    FBitmap.Canvas.Fill.Kind := TBrushKind.Solid;
    FBitmap.Canvas.Fill.Color := FNumFillColor;
    if FNumSquare then
      FBitmap.Canvas.FillRect(R, 1)
    else
      FBitmap.Canvas.FillEllipse(R, 1);

    { Цифра по центру. Размер шрифта подбирается по ширине текста, чтобы
      число не выходило за границы фигуры: для круга запас больше, так как
      цифра должна помещаться ещё и внутри окружности. }
    S := IntToStr(ANumber);
    FBitmap.Canvas.Font.Family := 'Segoe UI';
    FBitmap.Canvas.Font.Style := [TFontStyle.fsBold];
    if FNumSquare then
      MaxW := D * 0.86
    else
      MaxW := D * 0.6;
    FBitmap.Canvas.Font.Size := D * 0.6;
    while FBitmap.Canvas.TextWidth(S) > MaxW do
    begin
      FBitmap.Canvas.Font.Size := FBitmap.Canvas.Font.Size - 1;
      if FBitmap.Canvas.Font.Size < 4 then
        Break;
    end;

    FBitmap.Canvas.Fill.Color := FNumTextColor;
    FBitmap.Canvas.FillText(R, S, False, 1, [],
      TTextAlign.Center, TTextAlign.Center);
    { Сброс стиля шрифта: иначе жирный останется на канвасе и текстовая
      подпись после нумератора тоже стала бы жирной. }
    FBitmap.Canvas.Font.Style := [];
  finally
    FBitmap.Canvas.EndScene;
  end;
end;

procedure TQSEditorForm.CommitShape;
var
  R: TRectF;
  IR: TRect;
  Radius: Integer;
begin
  if FBitmap.IsEmpty then
    Exit;

  R := NormalizedDragRect;

  { Линия/стрелка и маркер строятся по двум точкам, поэтому размер
    охватывающего прямоугольника не проверяется. Нумератор ставится
    одиночным кликом и тоже не зависит от размера выделения. }
  if (FTool = etLine) or (FTool = etMarker) or (FTool = etNumber) then
  begin
    if FTool = etNumber then
    begin
      { Следующий порядковый номер ставится по центру точки клика. }
      Inc(FNumCounter);
      PushUndo;
      DrawNumberMarkerOnBitmap(FStartPoint, FNumCounter);
    end
    else
    begin
      if (Abs(FCurrentPoint.X - FStartPoint.X) < 2) and
        (Abs(FCurrentPoint.Y - FStartPoint.Y) < 2) then
      begin
        if FTool = etMarker then
          UpdateStatus('Маркер слишком короткий: протяните мышь от начала к концу.')
        else if FArrowHead then
          UpdateStatus('Стрелка слишком короткая: протяните мышь от начала к концу.')
        else
          UpdateStatus('Линия слишком короткая: протяните мышь от начала к концу.');
        Exit;
      end;
      PushUndo;
      if FTool = etMarker then
        DrawMarkerOnBitmap(FStartPoint, FCurrentPoint)
      else
        DrawArrowOnBitmap(FStartPoint, FCurrentPoint);
    end;
  end
  else
  begin
    if (R.Width < 2) or (R.Height < 2) then
    begin
      if FTool = etText then
        R := RectF(FStartPoint.X, FStartPoint.Y,
          Min(FBitmap.Width, FStartPoint.X + 420 + FTextPadding * 2),
          Min(FBitmap.Height,
            FStartPoint.Y + FTextSize * 2.2 + FTextPadding * 2))
      else
        Exit;
    end;

    case FTool of
      etText:
        begin
          if Trim(FTextEdit.Text) = '' then
          begin
            UpdateStatus('Сначала введите текст в поле "Текст подписи".');
            Exit;
          end;
          PushUndo;
          DrawTextOnBitmap(R);
        end;

      etRectangle:
        begin
          PushUndo;
          DrawRectangleOnBitmap(R);
        end;

      etEllipse:
        begin
          PushUndo;
          DrawEllipseOnBitmap(R);
        end;

      etBlur:
        begin
          if (R.Width < 3) or (R.Height < 3) then
            Exit;
          IR := Rect(Round(R.Left), Round(R.Top),
            Round(R.Right), Round(R.Bottom));
          Radius := EnsureRange(Round(Min(R.Width, R.Height) / 10), 3, 40);
          PushUndo;
          QSBlurBitmap(FBitmap, IR, Radius);
        end;

      etCrop:
        begin
          if (R.Width < 4) or (R.Height < 4) then
          begin
            UpdateStatus('Обрезка слишком мала: выделите область побольше.');
            Exit;
          end;
          if not CropSelected(R) then
            Exit;
        end;
    end;
  end;

  UpdateCaption;
  UpdateStatus(Format('Готово. Размер снимка: %d x %d.',
    [FBitmap.Width, FBitmap.Height]));
  if FPaintBox <> nil then
    FPaintBox.Repaint;
end;

function TQSEditorForm.CropSelected(const R: TRectF): Boolean;
var
  IR: TRect;
  NB: TBitmap;
begin
  Result := False;
  if (FBitmap = nil) or FBitmap.IsEmpty then
    Exit;

  IR := Rect(Round(R.Left), Round(R.Top),
    Round(R.Right), Round(R.Bottom));
  { QSCropBitmap сам нормализует прямоугольник, подрезает до границ
    снимка и отказывается от пустой области. }
  NB := QSCropBitmap(FBitmap, IR);
  if NB = nil then
  begin
    UpdateStatus('Не удалось обрезать изображение.');
    Exit;
  end;
  try
    PushUndo;
    QSCopyBitmap(NB, FBitmap);
  finally
    NB.Free;
  end;
  ClampZoomOffset;
  Result := True;
end;

{ ------------------------------------------------------------------ }
{ Отображение и мышь                                                 }
{ ------------------------------------------------------------------ }

function TQSEditorForm.GetDestRect: TRectF;
begin
  Result := RectF(0, 0, 0, 0);
  if (FBitmap = nil) or FBitmap.IsEmpty or (FPaintBox = nil) then
    Exit;
  { Прямоугольник изображения в окне: масштаб FZoom и сдвиг FOffset. }
  Result := RectF(FOffset.X, FOffset.Y,
    FOffset.X + FBitmap.Width * FZoom,
    FOffset.Y + FBitmap.Height * FZoom);
end;

function TQSEditorForm.ScreenToImage(const APoint: TPointF): TPointF;
begin
  Result := PointF(0, 0);
  if (FBitmap = nil) or FBitmap.IsEmpty or (FZoom <= 0) then
    Exit;
  Result := PointF(
    EnsureRange((APoint.X - FOffset.X) / FZoom, 0, FBitmap.Width),
    EnsureRange((APoint.Y - FOffset.Y) / FZoom, 0, FBitmap.Height));
end;

function TQSEditorForm.NormalizedDragRect: TRectF;
begin
  Result := RectF(
    Min(FStartPoint.X, FCurrentPoint.X),
    Min(FStartPoint.Y, FCurrentPoint.Y),
    Max(FStartPoint.X, FCurrentPoint.X),
    Max(FStartPoint.Y, FCurrentPoint.Y));
end;

function TQSEditorForm.ImageRectToDest(const AImageRect,
  ADestRect: TRectF): TRectF;
var
  SX, SY: Single;
begin
  if (FBitmap = nil) or FBitmap.IsEmpty then
    Exit(RectF(0, 0, 0, 0));
  SX := ADestRect.Width / FBitmap.Width;
  SY := ADestRect.Height / FBitmap.Height;
  Result := RectF(
    ADestRect.Left + AImageRect.Left * SX,
    ADestRect.Top + AImageRect.Top * SY,
    ADestRect.Left + AImageRect.Right * SX,
    ADestRect.Top + AImageRect.Bottom * SY);
end;

function TQSEditorForm.ImagePointToDest(const APoint: TPointF;
  const ADestRect: TRectF): TPointF;
var
  SX, SY: Single;
begin
  if (FBitmap = nil) or FBitmap.IsEmpty then
    Exit(PointF(0, 0));
  SX := ADestRect.Width / FBitmap.Width;
  SY := ADestRect.Height / FBitmap.Height;
  Result := PointF(ADestRect.Left + APoint.X * SX,
    ADestRect.Top + APoint.Y * SY);
end;

procedure TQSEditorForm.SetZoom(ANewZoom: Single; AAnchor: TPointF);
var
  Mp: TPointF;
begin
  if (FBitmap = nil) or FBitmap.IsEmpty or (FPaintBox = nil) then
    Exit;
  ANewZoom := EnsureRange(ANewZoom, QSZoomMin, QSZoomMax);
  if SameValue(ANewZoom, FZoom) then
    Exit;

  { Точка изображения AAnchor должна остаться под той же точкой экрана:
    масштабирование идёт относительно неё. }
  Mp := ImagePointToDest(AAnchor, GetDestRect);
  FZoom := ANewZoom;
  FOffset := PointF(Mp.X - AAnchor.X * FZoom, Mp.Y - AAnchor.Y * FZoom);
  ClampZoomOffset;
  UpdateZoomLabel;
  FPaintBox.Repaint;
end;

procedure TQSEditorForm.ClampZoomOffset;
var
  W, H, BoxW, BoxH: Single;
begin
  if (FBitmap = nil) or FBitmap.IsEmpty or (FPaintBox = nil) then
    Exit;
  BoxW := FPaintBox.Width;
  BoxH := FPaintBox.Height;
  W := FBitmap.Width * FZoom;
  H := FBitmap.Height * FZoom;

  { Если изображение меньше окна - центрируем; иначе не даём увести его
    за границы (минимум края остаётся достижимым прокруткой). }
  if W <= BoxW then
    FOffset.X := (BoxW - W) / 2
  else
    FOffset.X := EnsureRange(FOffset.X, BoxW - W, 0);
  if H <= BoxH then
    FOffset.Y := (BoxH - H) / 2
  else
    FOffset.Y := EnsureRange(FOffset.Y, BoxH - H, 0);
end;

procedure TQSEditorForm.UpdateZoomLabel;
begin
  if FZoomLabel <> nil then
    FZoomLabel.Text := IntToStr(Round(FZoom * 100)) + '%';
end;

procedure TQSEditorForm.FitZoomToWindow;
var
  S: Single;
begin
  if (FBitmap = nil) or FBitmap.IsEmpty or (FPaintBox = nil) then
    Exit;
  if (FPaintBox.Width <= 0) or (FPaintBox.Height <= 0) then
    Exit; { Раскладка ещё не готова - впишем при первом Resize. }

  S := Min(FPaintBox.Width / FBitmap.Width, FPaintBox.Height / FBitmap.Height);
  if S > 1 then
    S := 1; { Мелкие снимки не увеличиваем. }
  S := EnsureRange(S, QSZoomMin, QSZoomMax);
  FFitOnLoad := False;
  FZoom := S;
  ClampZoomOffset;
  UpdateZoomLabel;
end;

procedure TQSEditorForm.DrawPreview(ACanvas: TCanvas;
  const ADestRect: TRectF);
var
  R: TRectF;
  TR: TRectF;
  Scale, FillOp, D: Single;
  Text: string;
  PStart, PEnd, PLineEnd, C: TPointF;
  HeadLen, Angle, Base: Single;
  P1, P2: TPointF;
  Poly: TPolygon;
begin
  Scale := ADestRect.Width / FBitmap.Width;

  ACanvas.Stroke.Kind := TBrushKind.Solid;
  ACanvas.Stroke.Color := FPenColor;
  ACanvas.Stroke.Thickness := Max(1, FPenWidth * Scale);
  ACanvas.Stroke.Dash := TStrokeDash.Solid;

  ACanvas.Fill.Kind := TBrushKind.Solid;
  ACanvas.Fill.Color := FFillColor;

  { Линия предпросматривается по двум точкам, а не по прямоугольнику. }
  if FTool = etLine then
  begin
    PStart := ImagePointToDest(FStartPoint, ADestRect);
    PEnd := ImagePointToDest(FCurrentPoint, ADestRect);
    HeadLen := Max(10, FPenWidth * 4) * Scale;

    ACanvas.Stroke.Color := FPenColor;
    ACanvas.Stroke.Thickness := Max(1, FPenWidth * Scale);

    if FArrowHead then
      PLineEnd := ArrowBasePoint(PStart, PEnd, HeadLen)
    else
      PLineEnd := PEnd;

    ACanvas.DrawLine(PStart, PLineEnd, 1);

    if not FArrowHead then
      Exit;

    Angle := ArcTan2(PEnd.Y - PStart.Y, PEnd.X - PStart.X);
    Base := Angle + Pi;
    P1 := PointF(PEnd.X + HeadLen * Cos(Base + Pi / 7),
      PEnd.Y + HeadLen * Sin(Base + Pi / 7));
    P2 := PointF(PEnd.X + HeadLen * Cos(Base - Pi / 7),
      PEnd.Y + HeadLen * Sin(Base - Pi / 7));

    SetLength(Poly, 3);
    Poly[0] := PEnd;
    Poly[1] := P1;
    Poly[2] := P2;

    ACanvas.Fill.Color := FPenColor;
    ACanvas.FillPolygon(Poly, 1);
    Exit;
  end;

  { Маркер тоже строится по двум точкам. }
  if FTool = etMarker then
  begin
    PStart := ImagePointToDest(FStartPoint, ADestRect);
    PEnd := ImagePointToDest(FCurrentPoint, ADestRect);
    ACanvas.Stroke.Kind := TBrushKind.Solid;
    ACanvas.Stroke.Color := (FMarkerColor and $00FFFFFF) or
      (TAlphaColor(Round(FMarkerOpacity * 2.55)) shl 24);
    ACanvas.Stroke.Thickness := Max(1, FMarkerPenWidth * Scale);
    if FMarkerRoundCap then
      ACanvas.Stroke.Cap := TStrokeCap.Round
    else
      ACanvas.Stroke.Cap := TStrokeCap.Flat;
    ACanvas.DrawLine(PStart, PEnd, 1);
    Exit;
  end;

  { Нумератор: рамка-подсказка размером фигуры в точке курсора и подпись
    с номером, который будет поставлен следующим. }
  if FTool = etNumber then
  begin
    C := ImagePointToDest(FCurrentPoint, ADestRect);
    D := FNumSize * Scale;
    R := RectF(C.X - D / 2, C.Y - D / 2, C.X + D / 2, C.Y + D / 2);

    ACanvas.Stroke.Kind := TBrushKind.Solid;
    ACanvas.Stroke.Color := $FFEC1C24;
    ACanvas.Stroke.Thickness := 1;
    ACanvas.Stroke.Dash := TStrokeDash.Dash;
    if FNumSquare then
      ACanvas.DrawRect(R, 1)
    else
      ACanvas.DrawEllipse(R, 1);
    ACanvas.Stroke.Dash := TStrokeDash.Solid;

    ACanvas.Fill.Kind := TBrushKind.Solid;
    ACanvas.Fill.Color := $FFFFFFFF;
    ACanvas.Font.Family := 'Segoe UI';
    ACanvas.Font.Size := 12;
    ACanvas.FillText(RectF(R.Left + 4, R.Top - 22, R.Right - 4, R.Top - 2),
      'Номер ' + IntToStr(FNumCounter + 1), False, 1, [],
      TTextAlign.Leading, TTextAlign.Leading);
    Exit;
  end;

  R := ImageRectToDest(NormalizedDragRect, ADestRect);
  if (R.Width < 1) or (R.Height < 1) then
    Exit;

  case FTool of
    etRectangle:
      begin
        if FFillOpacity > 0 then
          ACanvas.FillRect(R, FFillOpacity / 100);
        ACanvas.DrawRect(R, 1);
      end;

    etEllipse:
      begin
        if FFillOpacity > 0 then
          ACanvas.FillEllipse(R, FFillOpacity / 100);
        ACanvas.DrawEllipse(R, 1);
      end;

    etText:
      begin
        { Полупрозрачный фон, если включён; иначе остаётся только
          пунктирная рамка-подсказка. }
        if FTextFill then
        begin
          FillOp := FFillOpacity / 100;
          if FillOp < 0.05 then
            FillOp := 0.05;
          if FillOp > 1 then
            FillOp := 1;
          ACanvas.FillRect(R, FillOp);
        end;

        if FTextBorder then
        begin
          ACanvas.Stroke.Dash := TStrokeDash.Solid;
          ACanvas.Stroke.Thickness := Max(1, FTextBorderWidth * Scale);
          ACanvas.DrawRect(R, 1);
        end
        else
        begin
          ACanvas.Stroke.Dash := TStrokeDash.Dash;
          ACanvas.DrawRect(R, 1);
          ACanvas.Stroke.Dash := TStrokeDash.Solid;
        end;

        Text := FTextEdit.Text;
        if Text <> '' then
        begin
          TR := InsetTextRect(R, FTextPadding * Scale);
          ACanvas.Fill.Kind := TBrushKind.Solid;
          ACanvas.Fill.Color := FPenColor;
          ACanvas.Font.Family := 'Segoe UI';
          ACanvas.Font.Size := Max(8, FTextSize * Scale);
          ACanvas.FillText(TR, Text, True, 1, [],
            TTextAlign.Leading, TTextAlign.Leading);
        end;
      end;

    etBlur:
      begin
        ACanvas.Stroke.Dash := TStrokeDash.Dash;
        ACanvas.DrawRect(R, 1);
        ACanvas.Stroke.Dash := TStrokeDash.Solid;

        ACanvas.Fill.Kind := TBrushKind.Solid;
        ACanvas.Fill.Color := $FFFFFFFF;
        ACanvas.Font.Family := 'Segoe UI';
        ACanvas.Font.Size := 12;
        ACanvas.FillText(RectF(R.Left + 6, R.Top + 4, R.Right - 6, R.Top + 26),
          'Размытие', False, 1, [], TTextAlign.Leading, TTextAlign.Leading);
      end;

    etCrop:
      begin
        { Тонкая красная пунктирная рамка выделения. Цвет и толщина заданы
          явно, чтобы не зависеть от параметров контура инструментов
          рисования (FPenColor/FPenWidth). }
        ACanvas.Stroke.Kind := TBrushKind.Solid;
        ACanvas.Stroke.Color := $FFEC1C24;
        ACanvas.Stroke.Thickness := 1;
        ACanvas.Stroke.Dash := TStrokeDash.Dash;
        ACanvas.DrawRect(R, 1);
        ACanvas.Stroke.Dash := TStrokeDash.Solid;

        ACanvas.Fill.Kind := TBrushKind.Solid;
        ACanvas.Fill.Color := $FFFFFFFF;
        ACanvas.Font.Family := 'Segoe UI';
        ACanvas.Font.Size := 12;
        ACanvas.FillText(RectF(R.Left + 6, R.Top + 4, R.Right - 6, R.Top + 26),
          'Обрезка', False, 1, [], TTextAlign.Leading, TTextAlign.Leading);
      end;
  end;
end;

procedure TQSEditorForm.PaintBoxPaint(Sender: TObject; Canvas: TCanvas);
var
  D: TRectF;
  S: TCanvasSaveState;
begin
  { При увеличении рисунок больше области рисования и выходит за её
    границы. FMX сам канвас не обрезает: без клиппинга изображение
    заливало статусную строку (кнопки масштаба и «1:1» выглядели
    «прозрачными»). Ограничиваем рисование областью PaintBox. }
  S := Canvas.SaveState;
  try
    Canvas.IntersectClipRect(RectF(0, 0, FPaintBox.Width, FPaintBox.Height));

    Canvas.Fill.Kind := TBrushKind.Solid;
    Canvas.Fill.Color := $FF1B1B1B;
    Canvas.FillRect(RectF(0, 0, FPaintBox.Width, FPaintBox.Height), 1);
    Canvas.Stroke.Dash := TStrokeDash.Solid;

    if (FBitmap = nil) or FBitmap.IsEmpty then
      Exit;

    D := GetDestRect;
    if (D.Width <= 0) or (D.Height <= 0) then
      Exit;

    Canvas.DrawBitmap(FBitmap, FBitmap.BoundsF, D, 1);
    if FDragging then
      DrawPreview(Canvas, D);
  finally
    Canvas.RestoreState(S);
  end;
end;

procedure TQSEditorForm.PaintBoxMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  { Средняя кнопка - прокрутка изображения (например, при большом зуме). }
  if Button = TMouseButton.mbMiddle then
  begin
    FPanning := True;
    FPanStartMouse := PointF(X, Y);
    FPanStartOffset := FOffset;
    if FPaintBox <> nil then
      FPaintBox.Cursor := crSizeAll;
    Exit;
  end;

  if Button <> TMouseButton.mbLeft then
    Exit;
  if (FBitmap = nil) or FBitmap.IsEmpty then
    Exit;

  { Клики по серому полю вокруг изображения игнорируем: иначе координата
    обрезалась бы к ближайшему краю и фигура появлялась у границы. }
  if not GetDestRect.Contains(PointF(X, Y)) then
    Exit;

  if FPaintBox.CanFocus then
    FPaintBox.SetFocus;

  FStartPoint := ScreenToImage(PointF(X, Y));
  FCurrentPoint := FStartPoint;
  FDragging := True;
  FPaintBox.Repaint;
end;

procedure TQSEditorForm.PaintBoxMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Single);
begin
  if FPanning then
  begin
    FOffset := PointF(
      FPanStartOffset.X + (X - FPanStartMouse.X),
      FPanStartOffset.Y + (Y - FPanStartMouse.Y));
    ClampZoomOffset;
    FPaintBox.Repaint;
    Exit;
  end;

  if not FDragging then
    Exit;
  FCurrentPoint := ScreenToImage(PointF(X, Y));
  FPaintBox.Repaint;
end;

procedure TQSEditorForm.PaintBoxMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  if Button = TMouseButton.mbMiddle then
  begin
    FPanning := False;
    if FPaintBox <> nil then
      FPaintBox.Cursor := crCross;
    Exit;
  end;

  if Button <> TMouseButton.mbLeft then
    Exit;
  if not FDragging then
    Exit;

  FCurrentPoint := ScreenToImage(PointF(X, Y));
  FDragging := False;

  CommitShape;
end;

procedure TQSEditorForm.PaintBoxMouseWheel(Sender: TObject;
  Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean);
var
  P: TPointF;
  Factor: Single;
begin
  if (FBitmap = nil) or FBitmap.IsEmpty then
    Exit;

  Handled := True;
  if WheelDelta > 0 then
    Factor := QSZoomStep
  else
    Factor := 1 / QSZoomStep;

  { Вверх - приблизить, вниз - отдалить. Масштабируем относительно
    точки под курсором. }
  P := ScreenToImage(FPaintBox.ScreenToLocal(Screen.MousePos));
  SetZoom(FZoom * Factor, P);
end;

procedure TQSEditorForm.PaintBoxResize(Sender: TObject);
begin
  if FFitOnLoad then
    FitZoomToWindow
  else
    ClampZoomOffset;
  if FPaintBox <> nil then
    FPaintBox.Repaint;
end;

procedure TQSEditorForm.EditorKeyDown(Sender: TObject; var Key: Word;
  var KeyChar: WideChar; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    Key := 0;
    KeyChar := #0;
    Close;
    Exit;
  end;

  if not (ssCtrl in Shift) then
    Exit;

  case Key of
    Ord('Z'):
      begin
        Key := 0;
        KeyChar := #0;
        if ssShift in Shift then
          DoRedo
        else
          DoUndo;
      end;
    Ord('Y'):
      begin
        Key := 0;
        KeyChar := #0;
        DoRedo;
      end;
    Ord('S'):
      begin
        Key := 0;
        KeyChar := #0;
        DoSave;
      end;
    Ord('C'):
      begin
        Key := 0;
        KeyChar := #0;
        DoCopy;
      end;
    Ord('0'):
      begin
        Key := 0;
        KeyChar := #0;
        BtnZoomResetClick(Self);
      end;
  end;
end;

{ ------------------------------------------------------------------ }
{ Действия                                                           }
{ ------------------------------------------------------------------ }

procedure TQSEditorForm.BtnUndoClick(Sender: TObject);
begin
  DoUndo;
end;

procedure TQSEditorForm.BtnRedoClick(Sender: TObject);
begin
  DoRedo;
end;

procedure TQSEditorForm.BtnCopyClick(Sender: TObject);
begin
  DoCopy;
end;

procedure TQSEditorForm.BtnSaveClick(Sender: TObject);
begin
  DoSave;
end;

procedure TQSEditorForm.BtnCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TQSEditorForm.BtnZoomInClick(Sender: TObject);
var
  P: TPointF;
begin
  if (FBitmap = nil) or FBitmap.IsEmpty or (FPaintBox = nil) then
    Exit;
  P := ScreenToImage(PointF(FPaintBox.Width / 2, FPaintBox.Height / 2));
  SetZoom(FZoom * QSZoomStep, P);
end;

procedure TQSEditorForm.BtnZoomOutClick(Sender: TObject);
var
  P: TPointF;
begin
  if (FBitmap = nil) or FBitmap.IsEmpty or (FPaintBox = nil) then
    Exit;
  P := ScreenToImage(PointF(FPaintBox.Width / 2, FPaintBox.Height / 2));
  SetZoom(FZoom / QSZoomStep, P);
end;

procedure TQSEditorForm.BtnZoomResetClick(Sender: TObject);
var
  P: TPointF;
begin
  if (FBitmap = nil) or FBitmap.IsEmpty or (FPaintBox = nil) then
    Exit;
  P := ScreenToImage(PointF(FPaintBox.Width / 2, FPaintBox.Height / 2));
  SetZoom(1, P);
end;

procedure TQSEditorForm.DoCopy;
begin
  if (FBitmap = nil) or FBitmap.IsEmpty then
    Exit;

  if QSCopyBitmapToClipboard(FBitmap) then
    UpdateStatus('Снимок скопирован в буфер обмена.')
  else
    ShowMessage('Не удалось скопировать изображение в буфер обмена.');
end;

procedure TQSEditorForm.DoSave;
var
  Dlg: TSaveDialog;
  FileName, Ext: string;
begin
  if (FBitmap = nil) or FBitmap.IsEmpty then
    Exit;

  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Title := 'Сохранить снимок';
    Dlg.Filter := 'PNG (*.png)|*.png|JPEG (*.jpg;*.jpeg)|*.jpg;*.jpeg';
    Dlg.FilterIndex := 1;
    Dlg.DefaultExt := 'png';
    Dlg.Options := [TOpenOption.ofOverwritePrompt];

    if FDefaultFileName = '' then
      FDefaultFileName := System.IOUtils.TPath.Combine(
        QSDefaultSaveFolder,
        QSAppCaption + '_' + FormatDateTime('yyyy-mm-dd_hh-nn-ss', Now) + '.png');

    { Диалог открывается в последнем использованном каталоге (общий с
      главным окном), в поле имени файла — только имя. }
    if (QSGlobalSettings <> nil) and
       DirectoryExists(QSGlobalSettings.LastSaveDir) then
      Dlg.InitialDir := QSGlobalSettings.LastSaveDir
    else
      Dlg.InitialDir := QSDefaultSaveFolder;
    Dlg.FileName := ExtractFileName(FDefaultFileName);

    if not Dlg.Execute then
      Exit;

    FileName := Dlg.FileName;
    Ext := LowerCase(ExtractFileExt(FileName));
    if Ext = '' then
    begin
      if Dlg.FilterIndex = 2 then
        FileName := FileName + '.jpg'
      else
        FileName := FileName + '.png';
    end;

    if QSSaveBitmap(FBitmap, FileName, 92) then
    begin
      FDefaultFileName := FileName;

      { Каталог сохранения общий с главным окном: запоминаем и сразу
        пишем в settings.ini. }
      if QSGlobalSettings <> nil then
      begin
        QSGlobalSettings.LastSaveDir := ExtractFileDir(FileName);
        QSGlobalSettings.Save;
      end;

      UpdateStatus('Сохранено: ' + FileName);
    end
    else
      ShowMessage('Не удалось сохранить файл. Проверьте папку и права доступа.');
  finally
    Dlg.Free;
  end;
end;

procedure TQSEditorForm.FormCloseHandler(Sender: TObject;
  var Action: TCloseAction);
begin
  { Окно не уничтожаем: оно переиспользуется при следующем снимке.
    Объект освобождается вместе с приложением. }
  SyncEditorSettings;
  if QSGlobalSettings <> nil then
    QSGlobalSettings.Save;
  Action := TCloseAction.caHide;
end;

procedure TQSEditorForm.FormShowHandler(Sender: TObject);
begin
  { На первом показе окна раскладка ещё не завершена, и FMX может
    запомнить устаревшие координаты перенесённых контролов (группа
    «Линия» при первом старте выглядела смещённой). Повторное
    применение геометрии после показа делает группы свойств
    стабильными - как и переключение инструментов туда-обратно. }
  ShowGroupForTool(FTool);
end;

end.
