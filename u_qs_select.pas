unit u_qs_select;

{
  QS Click - выбор области экрана.

  Оверлей реализован нативным окном Win32 на весь виртуальный рабочий стол.
  Это даёт:
    * точное попиксельное выделение на всех мониторах, включая мониторы
      с отрицательными координатами и разным масштабом DPI;
    * затемнение невыделенной части экрана;
    * отсутствие курсора мыши на итоговом снимке.

  Оверлей рисует заранее снятый снимок рабочего стола, поэтому в результат
  не попадают ни сам оверлей, ни курсор, ни всплывающие подсказки.
}

{$WARN SYMBOL_PLATFORM OFF}

interface

uses
  System.Types,
  FMX.Graphics;

/// <summary>
/// Показывает оверлей на всех мониторах и даёт выделить прямоугольник мышью.
/// AScreenRect получает выделенную область в физических координатах
/// виртуального рабочего стола.
/// Возвращает снимок выделенной области (владелец - вызывающий код)
/// или nil, если выбор отменён (Esc, правая кнопка, клик без протяжки).
/// </summary>
function QSSelectScreenRegion(out AScreenRect: TRect): FMX.Graphics.TBitmap;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Math,
  System.UITypes,
  Winapi.Windows,
  Winapi.Messages,
  { ВАЖНО: Winapi.Windows объявляет TBitmap = tagBITMAP (структура GDI).
    FMX.Graphics уже подключён в interface, поэтому здесь его повторять
    нельзя (E2004). Вместо этого тип FMX-снимка везде указан явно:
    FMX.Graphics.TBitmap. }
  u_qs_capture,
  FMX.Types;

const
  QSSelectClassName = 'QS-Click.SelectOverlay';
  QSSelectDimPercent = 42; { яркость затемнённой части, % }

type
  TQSSelectState = record
    Desktop: FMX.Graphics.TBitmap;
    VirtualRect: TRect;
    Width: Integer;
    Height: Integer;

    SrcDC: HDC;
    SrcBitmap: HBITMAP;
    SrcBits: Pointer;
    SrcOld: HGDIOBJ;

    DimDC: HDC;
    DimBitmap: HBITMAP;
    DimBits: Pointer;
    DimOld: HGDIOBJ;

    Wnd: HWND;
    Origin: TPoint;
    Current: TPoint;
    Dragging: Boolean;
    Done: Boolean;
    Canceled: Boolean;
    ScreenRect: TRect;
  end;
  PQSSelectState = ^TQSSelectState;

var
  GQSSelectState: TQSSelectState;
  GQSSelectClassRegistered: Boolean = False;

function QSLowWord(AValue: LPARAM): Integer; inline;
begin
  Result := Integer(LOWORD(NativeUInt(AValue)));
end;

function QSHighWord(AValue: LPARAM): Integer; inline;
begin
  Result := Integer(HIWORD(NativeUInt(AValue)));
end;

function QSPointFromLParam(AValue: LPARAM): TPoint; inline;
begin
  Result := Point(QSLowWord(AValue), QSHighWord(AValue));
end;

function QSNormalizedRect(const AP1, AP2: TPoint): TRect;
begin
  Result := Rect(Min(AP1.X, AP2.X), Min(AP1.Y, AP2.Y),
    Max(AP1.X, AP2.X), Max(AP1.Y, AP2.Y));
end;

function QSCreateTopDownDIB32(AWidth, AHeight: Integer;
  out ABits: Pointer): HBITMAP;
var
  BMI: TBitmapInfo;
  DC: HDC;
begin
  Result := 0;
  ABits := nil;
  if (AWidth <= 0) or (AHeight <= 0) then
    Exit;

  FillChar(BMI, SizeOf(BMI), 0);
  BMI.bmiHeader.biSize := SizeOf(TBitmapInfoHeader);
  BMI.bmiHeader.biWidth := AWidth;
  BMI.bmiHeader.biHeight := -AHeight;
  BMI.bmiHeader.biPlanes := 1;
  BMI.bmiHeader.biBitCount := 32;
  BMI.bmiHeader.biCompression := BI_RGB;
  BMI.bmiHeader.biSizeImage := AWidth * AHeight * 4;

  DC := GetDC(0);
  try
    if DC <> 0 then
      Result := CreateDIBSection(DC, BMI, DIB_RGB_COLORS, ABits, 0, 0);
  finally
    if DC <> 0 then
      ReleaseDC(0, DC);
  end;
end;

{ Копирует TBitmap в 32-битный DIB. При ADim = True яркость уменьшается. }
function QSFillDIBFromBitmap(ABitmap: FMX.Graphics.TBitmap; ABits: Pointer;
  ADim: Boolean): Boolean;
var
  Data: TBitmapData;
  W, H, X, Y, Factor: Integer;
  Src, Dst: PByte;
  C: TAlphaColor;
  B, G, R: Byte;
begin
  Result := False;
  if (ABitmap = nil) or ABitmap.IsEmpty or (ABits = nil) then
    Exit;
  if not ABitmap.Map(TMapAccess.Read, Data) then
    Exit;

  try
    W := ABitmap.Width;
    H := ABitmap.Height;
    if ADim then
      Factor := QSSelectDimPercent
    else
      Factor := 100;

    for Y := 0 to H - 1 do
    begin
      Src := PByte(Data.Data) + NativeInt(Y) * Data.Pitch;
      Dst := PByte(ABits) + NativeInt(Y) * W * 4;

      case Data.PixelFormat of
        TPixelFormat.BGRA:
          for X := 0 to W - 1 do
          begin
            B := Byte((Src[X * 4 + 0] * Cardinal(Factor)) div 100);
            G := Byte((Src[X * 4 + 1] * Cardinal(Factor)) div 100);
            R := Byte((Src[X * 4 + 2] * Cardinal(Factor)) div 100);
            Dst[X * 4 + 0] := B;
            Dst[X * 4 + 1] := G;
            Dst[X * 4 + 2] := R;
            Dst[X * 4 + 3] := $FF;
          end;

        TPixelFormat.RGBA:
          for X := 0 to W - 1 do
          begin
            R := Byte((Src[X * 4 + 0] * Cardinal(Factor)) div 100);
            G := Byte((Src[X * 4 + 1] * Cardinal(Factor)) div 100);
            B := Byte((Src[X * 4 + 2] * Cardinal(Factor)) div 100);
            Dst[X * 4 + 0] := B;
            Dst[X * 4 + 1] := G;
            Dst[X * 4 + 2] := R;
            Dst[X * 4 + 3] := $FF;
          end;

      else
        for X := 0 to W - 1 do
        begin
          C := Data.GetPixel(X, Y);
          B := Byte(((C and $FF) * Cardinal(Factor)) div 100);
          G := Byte((((C shr 8) and $FF) * Cardinal(Factor)) div 100);
          R := Byte((((C shr 16) and $FF) * Cardinal(Factor)) div 100);
          Dst[X * 4 + 0] := B;
          Dst[X * 4 + 1] := G;
          Dst[X * 4 + 2] := R;
          Dst[X * 4 + 3] := $FF;
        end;
      end;
    end;

    GdiFlush;
    Result := True;
  finally
    ABitmap.Unmap(Data);
  end;
end;

procedure QSDrawOverlayText(ADC: HDC; AX, AY: Integer; const AText: string;
  ATextColor: COLORREF; ABkColor: COLORREF; APadding: Integer);
var
  Font: HFONT;
  OldFont: HGDIOBJ;
  Brush: HBRUSH;
  R: TRect;
  Size: TSize;
  OldBkMode: Integer;
  OldTextColor: COLORREF;
begin
  if (ADC = 0) or (AText = '') then
    Exit;

  { Параметры fdwItalic/fdwUnderline/fdwStrikeOut в Winapi.Windows
    объявлены как DWORD, поэтому здесь нужны 0, а не Boolean. }
  Font := CreateFont(-MulDiv(9, GetDeviceCaps(ADC, LOGPIXELSY), 72),
    0, 0, 0, FW_SEMIBOLD, 0, 0, 0, DEFAULT_CHARSET,
    OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
    DEFAULT_PITCH or FF_DONTCARE, 'Segoe UI');
  if Font = 0 then
    Exit;

  OldFont := SelectObject(ADC, Font);
  try
    GetTextExtentPoint32(ADC, PChar(AText), Length(AText), Size);

    R := Rect(AX, AY, AX + Size.cx + APadding * 2,
      AY + Size.cy + APadding * 2);
    Brush := CreateSolidBrush(ABkColor);
    if Brush <> 0 then
    try
      FillRect(ADC, R, Brush);
    finally
      DeleteObject(Brush);
    end;

    OldBkMode := SetBkMode(ADC, TRANSPARENT);
    OldTextColor := SetTextColor(ADC, ATextColor);
    try
      TextOut(ADC, AX + APadding, AY + APadding, PChar(AText), Length(AText));
    finally
      SetTextColor(ADC, OldTextColor);
      SetBkMode(ADC, OldBkMode);
    end;
  finally
    SelectObject(ADC, OldFont);
    DeleteObject(Font);
  end;
end;

procedure QSPaintSelection(ADC: HDC; AState: PQSSelectState);
var
  R: TRect;
  Pen, OldPen: HPEN;
  OldBrush: HGDIOBJ;
  Text, Hint: string;
  TX, TY, HintX, HintY: Integer;
begin
  if (ADC = 0) or (AState = nil) then
    Exit;

  { Затемнённый снимок всего рабочего стола. }
  BitBlt(ADC, 0, 0, AState^.Width, AState^.Height,
    AState^.DimDC, 0, 0, SRCCOPY);

  if AState^.Dragging then
  begin
    R := QSNormalizedRect(AState^.Origin, AState^.Current);
    if (R.Width > 0) and (R.Height > 0) then
    begin
      { Выделенная часть - исходная яркость. }
      BitBlt(ADC, R.Left, R.Top, R.Width, R.Height,
        AState^.SrcDC, R.Left, R.Top, SRCCOPY);

      { Двойная рамка: тёмная снаружи, голубая внутри. }
      Pen := CreatePen(PS_SOLID, 3, RGB(0, 0, 0));
      if Pen <> 0 then
      try
        OldPen := SelectObject(ADC, Pen);
        OldBrush := SelectObject(ADC, GetStockObject(NULL_BRUSH));
        try
          Rectangle(ADC, R.Left - 1, R.Top - 1, R.Right + 1, R.Bottom + 1);
        finally
          SelectObject(ADC, OldBrush);
          SelectObject(ADC, OldPen);
        end;
      finally
        DeleteObject(Pen);
      end;

      Pen := CreatePen(PS_SOLID, 1, RGB(41, 198, 255));
      if Pen <> 0 then
      try
        OldPen := SelectObject(ADC, Pen);
        OldBrush := SelectObject(ADC, GetStockObject(NULL_BRUSH));
        try
          Rectangle(ADC, R.Left, R.Top, R.Right, R.Bottom);
        finally
          SelectObject(ADC, OldBrush);
          SelectObject(ADC, OldPen);
        end;
      finally
        DeleteObject(Pen);
      end;

      Text := Format('%d x %d', [R.Width, R.Height]);
      TX := R.Left;
      TY := R.Top - 34;
      if TY < 4 then
        TY := R.Top + 6;
      if TX + 120 > AState^.Width then
        TX := Max(4, R.Right - 124);
      QSDrawOverlayText(ADC, TX, TY, Text, RGB(255, 255, 255),
        RGB(24, 24, 24), 7);
    end;
  end;

  Hint := 'Выделите область мышью.  Esc или правая кнопка - отмена.';
  HintX := (AState^.Width - 430) div 2;
  if HintX < 12 then
    HintX := 12;
  HintY := 18;
  QSDrawOverlayText(ADC, HintX, HintY, Hint, RGB(255, 255, 255),
    RGB(24, 24, 24), 9);
end;

procedure QSSelectFinish(AState: PQSSelectState; ACancel: Boolean);
var
  R: TRect;
begin
  if (AState = nil) or AState^.Done then
    Exit;

  if not ACancel then
  begin
    R := QSNormalizedRect(AState^.Origin, AState^.Current);
    if (R.Width >= 3) and (R.Height >= 3) then
    begin
      AState^.ScreenRect := Rect(
        AState^.VirtualRect.Left + R.Left,
        AState^.VirtualRect.Top + R.Top,
        AState^.VirtualRect.Left + R.Right,
        AState^.VirtualRect.Top + R.Bottom);
      AState^.Canceled := False;
    end
    else
      AState^.Canceled := True;
  end
  else
    AState^.Canceled := True;

  AState^.Dragging := False;
  AState^.Done := True;
  if GetCapture = AState^.Wnd then
    ReleaseCapture;
  { WM_QUIT здесь не нужен: вложенный цикл сообщений проверяет Done
    после DispatchMessage и завершается сам. PostQuitMessage оставил бы
    WM_QUIT в очереди и завершил бы всё приложение. }
end;

function QSSelectWndProc(AWnd: HWND; AMsg: UINT; AWParam: WPARAM;
  ALParam: LPARAM): LRESULT; stdcall;
var
  State: PQSSelectState;
  P: TPoint;
  PS: TPaintStruct;
  DC: HDC;
begin
  State := PQSSelectState(GetWindowLongPtr(AWnd, GWLP_USERDATA));
  Result := 0;

  case AMsg of
    WM_ERASEBKGND:
      Result := 1;

    WM_PAINT:
      begin
        DC := BeginPaint(AWnd, PS);
        try
          if State <> nil then
            QSPaintSelection(DC, State);
        finally
          EndPaint(AWnd, PS);
        end;
        Result := 0;
      end;

    WM_LBUTTONDOWN:
      begin
        if State <> nil then
        begin
          State^.Origin := QSPointFromLParam(ALParam);
          State^.Current := State^.Origin;
          State^.Dragging := True;
          SetCapture(AWnd);
          InvalidateRect(AWnd, nil, False);
        end;
        Result := 0;
      end;

    WM_MOUSEMOVE:
      begin
        if (State <> nil) and State^.Dragging then
        begin
          P := QSPointFromLParam(ALParam);
          if (P.X <> State^.Current.X) or (P.Y <> State^.Current.Y) then
          begin
            State^.Current := P;
            InvalidateRect(AWnd, nil, False);
          end;
        end;
        Result := 0;
      end;

    WM_LBUTTONUP:
      begin
        if (State <> nil) and State^.Dragging then
        begin
          State^.Current := QSPointFromLParam(ALParam);
          QSSelectFinish(State, False);
        end;
        Result := 0;
      end;

    WM_RBUTTONDOWN, WM_MBUTTONDOWN:
      begin
        if State <> nil then
          QSSelectFinish(State, True);
        Result := 0;
      end;

    WM_KEYDOWN:
      begin
        if (State <> nil) and (AWParam = VK_ESCAPE) then
          QSSelectFinish(State, True);
        Result := 0;
      end;

    WM_SETCURSOR:
      begin
        SetCursor(LoadCursor(0, IDC_CROSS));
        Result := 1;
      end;

    WM_CLOSE:
      begin
        if State <> nil then
          QSSelectFinish(State, True);
        Result := 0;
      end;

    WM_DESTROY:
      begin
        { Если окно уничтожено извне (завершение сеанса, закрытие
          рабочего стола), вложенный цикл должен завершиться. }
        if State <> nil then
        begin
          State^.Canceled := True;
          State^.Done := True;
        end;
        Result := 0;
      end;
  else
    Result := DefWindowProc(AWnd, AMsg, AWParam, ALParam);
  end;
end;

procedure QSEnsureSelectClass;
var
  WC: TWndClass;
begin
  if GQSSelectClassRegistered then
    Exit;

  FillChar(WC, SizeOf(WC), 0);
  WC.style := CS_HREDRAW or CS_VREDRAW;
  WC.lpfnWndProc := @QSSelectWndProc;
  WC.hInstance := HInstance;
  WC.hCursor := LoadCursor(0, IDC_CROSS);
  WC.hbrBackground := 0;
  WC.lpszClassName := PChar(QSSelectClassName);
  if RegisterClass(WC) <> 0 then
    GQSSelectClassRegistered := True;
end;

procedure QSFreeSelectionResources(AState: PQSSelectState);
begin
  if AState = nil then
    Exit;

  if AState^.SrcDC <> 0 then
  begin
    if AState^.SrcOld <> 0 then
      SelectObject(AState^.SrcDC, AState^.SrcOld);
    DeleteDC(AState^.SrcDC);
    AState^.SrcDC := 0;
  end;

  if AState^.DimDC <> 0 then
  begin
    if AState^.DimOld <> 0 then
      SelectObject(AState^.DimDC, AState^.DimOld);
    DeleteDC(AState^.DimDC);
    AState^.DimDC := 0;
  end;

  if AState^.SrcBitmap <> 0 then
  begin
    DeleteObject(AState^.SrcBitmap);
    AState^.SrcBitmap := 0;
  end;

  if AState^.DimBitmap <> 0 then
  begin
    DeleteObject(AState^.DimBitmap);
    AState^.DimBitmap := 0;
  end;

  if (AState^.Wnd <> 0) and IsWindow(AState^.Wnd) then
  begin
    DestroyWindow(AState^.Wnd);
    AState^.Wnd := 0;
  end;

  AState^.Desktop.Free;
  AState^.Desktop := nil;
  AState^.SrcBits := nil;
  AState^.DimBits := nil;
end;

function QSSelectScreenRegion(out AScreenRect: TRect): FMX.Graphics.TBitmap;
var
  Msg: TMsg;
  ImageRect: TRect;
begin
  Result := nil;
  AScreenRect := Rect(0, 0, 0, 0);

  FillChar(GQSSelectState, SizeOf(GQSSelectState), 0);

  GQSSelectState.Desktop := QSCaptureDesktop;
  if GQSSelectState.Desktop = nil then
    Exit;

  GQSSelectState.VirtualRect := QSDesktopRect;
  GQSSelectState.Width := GQSSelectState.Desktop.Width;
  GQSSelectState.Height := GQSSelectState.Desktop.Height;
  if (GQSSelectState.Width <= 0) or (GQSSelectState.Height <= 0) then
  begin
    QSFreeSelectionResources(@GQSSelectState);
    Exit;
  end;

  GQSSelectState.SrcBitmap := QSCreateTopDownDIB32(
    GQSSelectState.Width, GQSSelectState.Height, GQSSelectState.SrcBits);
  if GQSSelectState.SrcBitmap = 0 then
  begin
    QSFreeSelectionResources(@GQSSelectState);
    Exit;
  end;
  if not QSFillDIBFromBitmap(GQSSelectState.Desktop,
    GQSSelectState.SrcBits, False) then
  begin
    QSFreeSelectionResources(@GQSSelectState);
    Exit;
  end;

  GQSSelectState.DimBitmap := QSCreateTopDownDIB32(
    GQSSelectState.Width, GQSSelectState.Height, GQSSelectState.DimBits);
  if GQSSelectState.DimBitmap = 0 then
  begin
    QSFreeSelectionResources(@GQSSelectState);
    Exit;
  end;
  if not QSFillDIBFromBitmap(GQSSelectState.Desktop,
    GQSSelectState.DimBits, True) then
  begin
    QSFreeSelectionResources(@GQSSelectState);
    Exit;
  end;

  GQSSelectState.SrcDC := CreateCompatibleDC(0);
  if GQSSelectState.SrcDC = 0 then
  begin
    QSFreeSelectionResources(@GQSSelectState);
    Exit;
  end;
  GQSSelectState.SrcOld := SelectObject(GQSSelectState.SrcDC,
    GQSSelectState.SrcBitmap);

  GQSSelectState.DimDC := CreateCompatibleDC(0);
  if GQSSelectState.DimDC = 0 then
  begin
    QSFreeSelectionResources(@GQSSelectState);
    Exit;
  end;
  GQSSelectState.DimOld := SelectObject(GQSSelectState.DimDC,
    GQSSelectState.DimBitmap);

  QSEnsureSelectClass;
  if not GQSSelectClassRegistered then
  begin
    QSFreeSelectionResources(@GQSSelectState);
    Exit;
  end;

  GQSSelectState.Wnd := CreateWindowEx(
    WS_EX_TOOLWINDOW or WS_EX_TOPMOST,
    QSSelectClassName, 'QS-Click',
    WS_POPUP,
    GQSSelectState.VirtualRect.Left,
    GQSSelectState.VirtualRect.Top,
    GQSSelectState.Width,
    GQSSelectState.Height,
    0, 0, HInstance, nil);

  if GQSSelectState.Wnd = 0 then
  begin
    QSFreeSelectionResources(@GQSSelectState);
    Exit;
  end;

  SetWindowLongPtr(GQSSelectState.Wnd, GWLP_USERDATA,
    LPARAM(@GQSSelectState));

  ShowWindow(GQSSelectState.Wnd, SW_SHOW);
  SetWindowPos(GQSSelectState.Wnd, HWND_TOPMOST,
    GQSSelectState.VirtualRect.Left, GQSSelectState.VirtualRect.Top,
    GQSSelectState.Width, GQSSelectState.Height,
    SWP_SHOWWINDOW);
  UpdateWindow(GQSSelectState.Wnd);
  SetForegroundWindow(GQSSelectState.Wnd);
  SetFocus(GQSSelectState.Wnd);

  { Вложенный цикл сообщений: приложение остаётся отзывчивым,
    а оверлей получает мышь и клавиатуру. }
  while not GQSSelectState.Done do
  begin
    if GetMessage(Msg, 0, 0, 0) = False then
      Break;
    TranslateMessage(Msg);
    DispatchMessage(Msg);
  end;

  if GQSSelectState.Canceled then
    AScreenRect := Rect(0, 0, 0, 0)
  else
  begin
    AScreenRect := GQSSelectState.ScreenRect;
    if (AScreenRect.Width > 0) and (AScreenRect.Height > 0) then
    begin
      ImageRect := Rect(
        AScreenRect.Left - GQSSelectState.VirtualRect.Left,
        AScreenRect.Top - GQSSelectState.VirtualRect.Top,
        AScreenRect.Right - GQSSelectState.VirtualRect.Left,
        AScreenRect.Bottom - GQSSelectState.VirtualRect.Top);
      Result := QSCropBitmap(GQSSelectState.Desktop, ImageRect);
    end;
  end;

  QSFreeSelectionResources(@GQSSelectState);
  FillChar(GQSSelectState, SizeOf(GQSSelectState), 0);
end;

end.
