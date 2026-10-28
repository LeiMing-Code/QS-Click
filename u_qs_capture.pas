unit u_qs_capture;

{
  QS Click - движок захвата экрана для FireMonkey (Windows).

  Реализовано только на штатных средствах Delphi 13 / FMX + Win32 API.
  Сторонние компоненты не требуются.

  Возможности:
    * снимок всего виртуального рабочего стола (все мониторы одним изображением);
    * снимок отдельного монитора (с корректным разрешением каждого дисплея);
    * снимок указанного окна (PrintWindow с запасным вариантом BitBlt);
    * снимок произвольного прямоугольника экрана;
    * сохранение в PNG / JPEG (через штатные кодеки FMX);
    * копирование изображения в буфер обмена (CF_DIB + PNG);
    * размытие произвольной области (box blur, три прохода).

  Курсор мыши в снимок не попадает: BitBlt и PrintWindow не рисуют курсор.
  Если когда-нибудь потребуется курсор, его нужно добавлять отдельно через
  GetCursorInfo + DrawIconEx.
}

{$WARN SYMBOL_PLATFORM OFF}

interface

uses
  System.SysUtils,
  System.Types,
  System.Classes,
  System.Math,
  System.UITypes,
  Winapi.Windows,
  Winapi.MultiMon,
  Winapi.DwmApi,
  { ВАЖНО: Winapi.Windows объявляет TBitmap (структура GDI tagBITMAP).
    Модули FMX должны идти последними, иначе TBitmap из FMX.Graphics
    затеняется и код вида TBitmap.Create не компилируется. }
  FMX.Graphics,
  FMX.Types;

type
  /// <summary>Информация о физическом мониторе (координаты в физических пикселях).</summary>
  TQSMonitorInfo = record
    Handle: HMONITOR;
    DeviceName: string;
    /// <summary>Полные границы монитора в координатах виртуального рабочего стола.</summary>
    Bounds: TRect;
    /// <summary>Рабочая область монитора (без панели задач).</summary>
    WorkArea: TRect;
    Primary: Boolean;
  end;

const
  /// <summary>Флаг PrintWindow для захвата содержимого окон с аппаратным ускорением.</summary>
  PW_RENDERFULLCONTENT = 2;

function PrintWindow(hWnd: HWND; hdcBlt: HDC; nFlags: UINT): BOOL; stdcall;
  external 'user32.dll' name 'PrintWindow';

{ В Winapi.Windows нет объявления GetShellWindow, добавляем его сами. }
function GetShellWindow: HWND; stdcall;
  external 'user32.dll' name 'GetShellWindow';

{ ------------------------------------------------------------------ }
{ Информация о дисплеях                                              }
{ ------------------------------------------------------------------ }

/// <summary>Список мониторов, упорядоченный слева-направо и сверху-вниз.</summary>
function QSMonitorList: TArray<TQSMonitorInfo>;

/// <summary>Прямоугольник всего виртуального рабочего стола в физических пикселях.</summary>
function QSDesktopRect: TRect;

/// <summary>Прямоугольник монитора по индексу; пустой, если индекс неверен.</summary>
function QSMonitorRect(AIndex: Integer): TRect;

/// <summary>Монитор, ближайший к указанному прямоугольнику.</summary>
function QSMonitorForRect(const ARect: TRect): TQSMonitorInfo;

/// <summary>Монитор, содержащий точку (или ближайший к ней).</summary>
function QSMonitorAtPoint(const APoint: TPoint): TQSMonitorInfo;

{ ------------------------------------------------------------------ }
{ Захват                                                             }
{ ------------------------------------------------------------------ }

/// <summary>
/// Снимок всего виртуального рабочего стола (все мониторы).
/// Возвращает новый TBitmap; владелец - вызывающий код.
/// </summary>
function QSCaptureDesktop: TBitmap;

/// <summary>
/// Снимок одного монитора по индексу из QSMonitorList.
/// Возвращает новый TBitmap и физические границы монитора.
/// </summary>
function QSCaptureMonitor(AIndex: Integer; out ABounds: TRect): TBitmap;

/// <summary>
/// Снимок прямоугольника экрана (физические координаты виртуального стола).
/// Возвращает новый TBitmap; владелец - вызывающий код.
/// </summary>
function QSCaptureRegion(const ARect: TRect): TBitmap;

/// <summary>
/// Снимок окна (включая невидимую часть, если PrintWindow это позволяет).
/// Возвращает новый TBitmap и физические границы снимка.
/// </summary>
function QSCaptureWindow(AWnd: HWND; out ABounds: TRect): TBitmap;

/// <summary>
/// Окно, которое сейчас активно. Если активно наше приложение, выбирается
/// первый подходящий видимый окон верхнего уровня из Z-порядка.
/// </summary>
function QSForegroundAppWindow: HWND;

/// <summary>Снимок активного окна.</summary>
function QSCaptureForegroundWindow(out ABounds: TRect): TBitmap;

/// <summary>Принадлежит ли окно текущему процессу.</summary>
function QSIsOwnProcessWindow(AWnd: HWND): Boolean;

{ ------------------------------------------------------------------ }
{ Готовые действия                                                   }
{ ------------------------------------------------------------------ }

/// <summary>
/// Сохранение в PNG/JPEG. Формат определяется расширением файла.
/// AQuality (1..100) применяется только к JPEG.
/// </summary>
function QSSaveBitmap(ABitmap: TBitmap; const AFileName: string; AQuality: Integer = 92): Boolean;

/// <summary>
/// Копирование изображения в буфер обмена Windows.
/// Кладятся одновременно CF_DIB и зарегистрированный формат "PNG".
/// </summary>
function QSCopyBitmapToClipboard(ABitmap: TBitmap): Boolean;

/// <summary>Полная независимая копия изображения. Владелец - вызывающий код.</summary>
function QSCloneBitmap(ABitmap: TBitmap): TBitmap;

/// <summary>
/// Обрезает изображение по прямоугольнику в пикселях изображения.
/// Возвращает новый TBitmap; владелец - вызывающий код.
/// </summary>
function QSCropBitmap(ABitmap: TBitmap; const ARect: TRect): TBitmap;

/// <summary>Копирует содержимое ASource в существующий ADest (размер меняется).</summary>
procedure QSCopyBitmap(ASource, ADest: TBitmap);

/// <summary>
/// Размытие области ABitmap (координаты в пикселях самого изображения).
/// ARadius - радиус в пикселях; используется три прохода box blur.
/// </summary>
procedure QSBlurBitmap(ABitmap: TBitmap; const ARect: TRect; ARadius: Integer);

/// <summary>
/// Включает Per-Monitor V2 DPI awareness, если манифест ещё не сделал этого.
/// Вызывается автоматически при загрузке модуля.
/// </summary>
procedure QSEnableDpiAwareness;

implementation

uses
  System.UIConsts;

type
  TMonitorEnumData = record
    Items: TArray<TQSMonitorInfo>;
    Count: Integer;
  end;
  PMonitorEnumData = ^TMonitorEnumData;

type
  TSetProcessDpiAwarenessContextProc = function(Value: DPI_AWARENESS_CONTEXT): BOOL; stdcall;

{ ------------------------------------------------------------------ }
{ Вспомогательные функции Win32                                      }
{ ------------------------------------------------------------------ }

function QSMonitorEnumProc(hMonitor: HMONITOR; hdcMonitor: HDC;
  lprcMonitor: PRect; dwData: LPARAM): BOOL; stdcall;
var
  Data: PMonitorEnumData;
  MI: TMonitorInfoEx;
begin
  Result := True;
  Data := PMonitorEnumData(dwData);
  if (Data = nil) or (lprcMonitor = nil) then
    Exit;

  FillChar(MI, SizeOf(MI), 0);
  MI.cbSize := SizeOf(MI);
  if not GetMonitorInfo(hMonitor, PMonitorInfo(@MI)) then
    Exit;

  if Data^.Count >= Length(Data^.Items) then
    SetLength(Data^.Items, Data^.Count + 4);

  with Data^.Items[Data^.Count] do
  begin
    Handle := hMonitor;
    DeviceName := StrPas(PWideChar(@MI.szDevice[0]));
    Bounds := MI.rcMonitor;
    WorkArea := MI.rcWork;
    Primary := (MI.dwFlags and MONITORINFOF_PRIMARY) <> 0;
  end;
  Inc(Data^.Count);
end;

function QSMonitorList: TArray<TQSMonitorInfo>;
var
  Data: TMonitorEnumData;
  I, J: Integer;
  Tmp: TQSMonitorInfo;
  MI: TMonitorInfo;
  R: TRect;
begin
  Data.Items := nil;
  Data.Count := 0;
  EnumDisplayMonitors(0, nil, @QSMonitorEnumProc, LPARAM(@Data));
  SetLength(Data.Items, Data.Count);

  { Упорядочиваем для стабильной нумерации "Монитор 1..N". }
  for I := 0 to High(Data.Items) - 1 do
    for J := I + 1 to High(Data.Items) do
      if (Data.Items[J].Bounds.Left < Data.Items[I].Bounds.Left) or
         ((Data.Items[J].Bounds.Left = Data.Items[I].Bounds.Left) and
          (Data.Items[J].Bounds.Top < Data.Items[I].Bounds.Top)) then
      begin
        Tmp := Data.Items[I];
        Data.Items[I] := Data.Items[J];
        Data.Items[J] := Tmp;
      end;

  if Length(Data.Items) = 0 then
  begin
    { Крайне редкий случай (например, сеанс без дисплея). }
    FillChar(MI, SizeOf(MI), 0);
    MI.cbSize := SizeOf(MI);
    if GetMonitorInfo(MonitorFromPoint(Point(0, 0), MONITOR_DEFAULTTOPRIMARY), @MI) then
      R := MI.rcMonitor
    else
      R := Rect(0, 0, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN));
    SetLength(Data.Items, 1);
    Data.Items[0].Handle := 0;
    Data.Items[0].DeviceName := '';
    Data.Items[0].Bounds := R;
    Data.Items[0].WorkArea := R;
    Data.Items[0].Primary := True;
  end;

  Result := Data.Items;
end;

function QSDesktopRect: TRect;
begin
  Result := Rect(
    GetSystemMetrics(SM_XVIRTUALSCREEN),
    GetSystemMetrics(SM_YVIRTUALSCREEN),
    GetSystemMetrics(SM_XVIRTUALSCREEN) + GetSystemMetrics(SM_CXVIRTUALSCREEN),
    GetSystemMetrics(SM_YVIRTUALSCREEN) + GetSystemMetrics(SM_CYVIRTUALSCREEN));

  if (Result.Width <= 0) or (Result.Height <= 0) then
    Result := Rect(0, 0, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN));
end;

function QSMonitorRect(AIndex: Integer): TRect;
var
  Monitors: TArray<TQSMonitorInfo>;
begin
  Monitors := QSMonitorList;
  if (AIndex >= 0) and (AIndex < Length(Monitors)) then
    Result := Monitors[AIndex].Bounds
  else
    Result := Rect(0, 0, 0, 0);
end;

function QSMonitorForRect(const ARect: TRect): TQSMonitorInfo;
var
  H: HMONITOR;
  MI: TMonitorInfoEx;
begin
  FillChar(Result, SizeOf(Result), 0);
  FillChar(MI, SizeOf(MI), 0);
  MI.cbSize := SizeOf(MI);

  H := MonitorFromRect(@ARect, MONITOR_DEFAULTTONEAREST);
  if GetMonitorInfo(H, PMonitorInfo(@MI)) then
  begin
    Result.Handle := H;
    Result.DeviceName := StrPas(PWideChar(@MI.szDevice[0]));
    Result.Bounds := MI.rcMonitor;
    Result.WorkArea := MI.rcWork;
    Result.Primary := (MI.dwFlags and MONITORINFOF_PRIMARY) <> 0;
  end
  else
  begin
    Result.Bounds := ARect;
    Result.WorkArea := ARect;
  end;
end;

function QSMonitorAtPoint(const APoint: TPoint): TQSMonitorInfo;
var
  Monitors: TArray<TQSMonitorInfo>;
  I: Integer;
begin
  Monitors := QSMonitorList;
  for I := 0 to High(Monitors) do
    if PtInRect(Monitors[I].Bounds, APoint) then
      Exit(Monitors[I]);

  FillChar(Result, SizeOf(Result), 0);
  Result := QSMonitorForRect(Rect(APoint.X, APoint.Y, APoint.X + 1, APoint.Y + 1));
end;

function QSIsOwnProcessWindow(AWnd: HWND): Boolean;
var
  Pid: DWORD;
begin
  Result := False;
  if AWnd = 0 then
    Exit;
  Pid := 0;
  GetWindowThreadProcessId(AWnd, Pid);
  Result := Pid = GetCurrentProcessId;
end;

{ ------------------------------------------------------------------ }
{ DIB / TBitmap                                                      }
{ ------------------------------------------------------------------ }

function QSCreateTopDownDIB(AWidth, AHeight: Integer; out ABits: Pointer): HBITMAP;
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
  BMI.bmiHeader.biHeight := -AHeight; { top-down DIB }
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

function QSBitmapFromDIB(ADIB: HBITMAP; ABits: Pointer;
  AWidth, AHeight: Integer): TBitmap;
var
  Data: TBitmapData;
  Src, Dst: PByte;
  X, Y: Integer;
  R, G, B: Byte;
begin
  Result := nil;
  if (ADIB = 0) or (ABits = nil) or (AWidth <= 0) or (AHeight <= 0) then
    Exit;

  Result := TBitmap.Create;
  try
    Result.SetSize(AWidth, AHeight);
    if not Result.Map(TMapAccess.Write, Data) then
      raise Exception.Create('QS Click: не удалось получить доступ к пикселям TBitmap.');

    try
      for Y := 0 to AHeight - 1 do
      begin
        Src := PByte(ABits) + NativeInt(Y) * AWidth * 4;
        Dst := PByte(Data.Data) + NativeInt(Y) * Data.Pitch;

        case Data.PixelFormat of
          TPixelFormat.BGRA:
            begin
              Move(Src^, Dst^, AWidth * 4);
              { BitBlt/PrintWindow оставляют байт альфы нулевым. }
              for X := 0 to AWidth - 1 do
                PByte(Dst + X * 4 + 3)^ := $FF;
            end;

          TPixelFormat.RGBA:
            begin
              for X := 0 to AWidth - 1 do
              begin
                Dst[X * 4 + 0] := Src[X * 4 + 2];
                Dst[X * 4 + 1] := Src[X * 4 + 1];
                Dst[X * 4 + 2] := Src[X * 4 + 0];
                Dst[X * 4 + 3] := $FF;
              end;
            end;

        else
          for X := 0 to AWidth - 1 do
          begin
            B := Src[X * 4 + 0];
            G := Src[X * 4 + 1];
            R := Src[X * 4 + 2];
            Data.SetPixel(X, Y,
              TAlphaColor($FF000000 or (Cardinal(R) shl 16) or
                          (Cardinal(G) shl 8) or Cardinal(B)));
          end;
        end;
      end;
    finally
      Result.Unmap(Data);
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure QSCopyBitmap(ASource, ADest: TBitmap);
begin
  if (ASource = nil) or (ADest = nil) then
    Exit;
  ADest.Assign(ASource);
end;

function QSCloneBitmap(ABitmap: TBitmap): TBitmap;
begin
  Result := nil;
  if (ABitmap = nil) or ABitmap.IsEmpty then
    Exit;

  Result := TBitmap.Create;
  try
    Result.Assign(ABitmap);
  except
    Result.Free;
    raise;
  end;
end;

function QSCropBitmap(ABitmap: TBitmap; const ARect: TRect): TBitmap;
var
  R, Bounds: TRect;
begin
  Result := nil;
  if (ABitmap = nil) or ABitmap.IsEmpty then
    Exit;

  R := ARect;
  R.NormalizeRect;
  Bounds := Rect(0, 0, ABitmap.Width, ABitmap.Height);
  if not IntersectRect(R, R, Bounds) then
    Exit;
  if (R.Width <= 0) or (R.Height <= 0) then
    Exit;

  Result := TBitmap.Create;
  try
    Result.SetSize(R.Width, R.Height);
    Result.CopyFromBitmap(ABitmap, R, 0, 0);
  except
    Result.Free;
    raise;
  end;
end;

function QSDIBLooksEmpty(ABits: Pointer; AWidth, AHeight: Integer): Boolean;
var
  X, Y, StepX, StepY: Integer;
  Line: PByte;
  Pixel: PCardinal;
begin
  Result := True;
  if (ABits = nil) or (AWidth <= 0) or (AHeight <= 0) then
    Exit;

  StepX := Max(1, AWidth div 48);
  StepY := Max(1, AHeight div 48);

  Y := 0;
  while Y < AHeight do
  begin
    { Не используем P[X] для PCardinal: в некоторых конфигурациях
      RTL указательная арифметика для этого типа выключена (E2016). }
    Line := PByte(ABits) + NativeInt(Y) * AWidth * 4;
    X := 0;
    while X < AWidth do
    begin
      Pixel := PCardinal(Line + NativeInt(X) * 4);
      if (Pixel^ and $00FFFFFF) <> 0 then
        Exit(False);
      Inc(X, StepX);
    end;
    Inc(Y, StepY);
  end;
end;

function QSCaptureRectFromDC(ASourceDC: HDC; const ASourceRect: TRect;
  AWidth, AHeight: Integer; out ADIB: HBITMAP; out ABits: Pointer): Boolean;
var
  MemDC: HDC;
  Old: HGDIOBJ;
begin
  Result := False;
  ADIB := 0;
  ABits := nil;
  if (ASourceDC = 0) or (AWidth <= 0) or (AHeight <= 0) then
    Exit;

  ADIB := QSCreateTopDownDIB(AWidth, AHeight, ABits);
  if ADIB = 0 then
    Exit;

  MemDC := CreateCompatibleDC(ASourceDC);
  if MemDC = 0 then
  begin
    DeleteObject(ADIB);
    ADIB := 0;
    ABits := nil;
    Exit;
  end;

  try
    Old := SelectObject(MemDC, ADIB);
    if Old = 0 then
    begin
      DeleteObject(ADIB);
      ADIB := 0;
      ABits := nil;
      Exit;
    end;
    try
      Result := BitBlt(MemDC, 0, 0, AWidth, AHeight,
        ASourceDC, ASourceRect.Left, ASourceRect.Top, SRCCOPY);
      GdiFlush;
    finally
      SelectObject(MemDC, Old);
    end;
  finally
    DeleteDC(MemDC);
  end;

  if not Result then
  begin
    DeleteObject(ADIB);
    ADIB := 0;
    ABits := nil;
  end;
end;

{ ------------------------------------------------------------------ }
{ Захват экрана и мониторов                                          }
{ ------------------------------------------------------------------ }

function QSCaptureRegion(const ARect: TRect): TBitmap;
var
  R: TRect;
  ScreenDC: HDC;
  DIB: HBITMAP;
  Bits: Pointer;
begin
  Result := nil;

  R := ARect;
  R.NormalizeRect;
  if not IntersectRect(R, R, QSDesktopRect) then
    Exit;

  ScreenDC := GetDC(0);
  if ScreenDC = 0 then
    Exit;
  try
    if QSCaptureRectFromDC(ScreenDC, R, R.Width, R.Height, DIB, Bits) then
    try
      Result := QSBitmapFromDIB(DIB, Bits, R.Width, R.Height);
    finally
      DeleteObject(DIB);
    end;
  finally
    ReleaseDC(0, ScreenDC);
  end;
end;

function QSCaptureDesktop: TBitmap;
var
  V: TRect;
  W, H: Integer;
  ScreenDC, MemDC, MonitorDC: HDC;
  DIB: HBITMAP;
  Bits: Pointer;
  Old: HGDIOBJ;
  Monitors: TArray<TQSMonitorInfo>;
  M: TQSMonitorInfo;
  X, Y: Integer;
begin
  Result := nil;
  V := QSDesktopRect;
  W := V.Width;
  H := V.Height;
  if (W <= 0) or (H <= 0) then
    Exit;

  DIB := QSCreateTopDownDIB(W, H, Bits);
  if DIB = 0 then
    Exit;

  ScreenDC := GetDC(0);
  if ScreenDC = 0 then
  begin
    DeleteObject(DIB);
    Exit;
  end;

  MemDC := CreateCompatibleDC(ScreenDC);
  if MemDC = 0 then
  begin
    ReleaseDC(0, ScreenDC);
    DeleteObject(DIB);
    Exit;
  end;

  try
    Old := SelectObject(MemDC, DIB);
    if Old = 0 then
    begin
      DeleteObject(DIB);
      DIB := 0;
      Exit;
    end;

    try
      { Собираем изображение с каждого монитора в его собственном разрешении.
        Это важно при разных масштабах DPI на разных экранах. }
      Monitors := QSMonitorList;
      if Length(Monitors) = 0 then
      begin
        BitBlt(MemDC, 0, 0, W, H, ScreenDC, V.Left, V.Top, SRCCOPY);
      end
      else
      begin
        for M in Monitors do
        begin
          X := M.Bounds.Left - V.Left;
          Y := M.Bounds.Top - V.Top;

          MonitorDC := 0;
          if M.DeviceName <> '' then
            MonitorDC := CreateDC('DISPLAY', PChar(M.DeviceName), nil, nil);

          if MonitorDC <> 0 then
          begin
            try
              if not BitBlt(MemDC, X, Y, M.Bounds.Width, M.Bounds.Height,
                MonitorDC, 0, 0, SRCCOPY) then
                BitBlt(MemDC, X, Y, M.Bounds.Width, M.Bounds.Height,
                  ScreenDC, M.Bounds.Left, M.Bounds.Top, SRCCOPY);
            finally
              DeleteDC(MonitorDC);
            end;
          end
          else
            BitBlt(MemDC, X, Y, M.Bounds.Width, M.Bounds.Height,
              ScreenDC, M.Bounds.Left, M.Bounds.Top, SRCCOPY);
        end;
      end;

      GdiFlush;
    finally
      SelectObject(MemDC, Old);
    end;
  finally
    DeleteDC(MemDC);
    ReleaseDC(0, ScreenDC);
  end;

  try
    Result := QSBitmapFromDIB(DIB, Bits, W, H);
  finally
    DeleteObject(DIB);
  end;
end;

function QSCaptureMonitor(AIndex: Integer; out ABounds: TRect): TBitmap;
var
  Monitors: TArray<TQSMonitorInfo>;
  M: TQSMonitorInfo;
  W, H: Integer;
  MonitorDC, MemDC: HDC;
  DIB: HBITMAP;
  Bits: Pointer;
  Old: HGDIOBJ;
  Temp: TBitmap;
begin
  Result := nil;
  ABounds := Rect(0, 0, 0, 0);

  Monitors := QSMonitorList;
  if (AIndex < 0) or (AIndex >= Length(Monitors)) then
    Exit;

  M := Monitors[AIndex];
  W := M.Bounds.Width;
  H := M.Bounds.Height;

  MonitorDC := 0;
  if M.DeviceName <> '' then
    MonitorDC := CreateDC('DISPLAY', PChar(M.DeviceName), nil, nil);

  if MonitorDC = 0 then
  begin
    { Запасной путь - копируем прямоугольник с общего экранного DC. }
    Result := QSCaptureRegion(M.Bounds);
    if Result <> nil then
      ABounds := M.Bounds;
    Exit;
  end;

  DIB := 0;
  Bits := nil;
  MemDC := 0;
  try
    DIB := QSCreateTopDownDIB(W, H, Bits);
    if DIB = 0 then
      Exit;

    MemDC := CreateCompatibleDC(MonitorDC);
    if MemDC = 0 then
      Exit;

    Old := SelectObject(MemDC, DIB);
    if Old = 0 then
      Exit;

    try
      if not BitBlt(MemDC, 0, 0, W, H, MonitorDC, 0, 0, SRCCOPY) then
      begin
        { Некоторые драйверы не отдают DC монитора - пробуем экран. }
        SelectObject(MemDC, Old);
        DeleteDC(MemDC);
        MemDC := 0;
        DeleteObject(DIB);
        DIB := 0;
        Result := QSCaptureRegion(M.Bounds);
        if Result <> nil then
          ABounds := M.Bounds;
        Exit;
      end;
      GdiFlush;
    finally
      SelectObject(MemDC, Old);
    end;

    Temp := QSBitmapFromDIB(DIB, Bits, W, H);
    Result := Temp;
    ABounds := M.Bounds;
  finally
    if MemDC <> 0 then
      DeleteDC(MemDC);
    if DIB <> 0 then
      DeleteObject(DIB);
    DeleteDC(MonitorDC);
  end;
end;

{ ------------------------------------------------------------------ }
{ Захват окна                                                        }
{ ------------------------------------------------------------------ }

function QSGetWindowBounds(AWnd: HWND): TRect;
var
  R: TRect;
  DwmRect: TRect;
  HR: HRESULT;
begin
  Result := Rect(0, 0, 0, 0);
  HR := DwmGetWindowAttribute(AWnd, DWMWA_EXTENDED_FRAME_BOUNDS,
    @DwmRect, SizeOf(DwmRect));
  if (HR = S_OK) and (DwmRect.Width > 0) and (DwmRect.Height > 0) then
    Result := DwmRect
  else if GetWindowRect(AWnd, R) then
    Result := R;
end;

function QSCaptureWindow(AWnd: HWND; out ABounds: TRect): TBitmap;
var
  R, V, Intersect: TRect;
  W, H: Integer;
  ScreenDC, MemDC: HDC;
  DIB: HBITMAP;
  Bits: Pointer;
  Old: HGDIOBJ;
  Ok: Boolean;
begin
  Result := nil;
  ABounds := Rect(0, 0, 0, 0);

  if (AWnd = 0) or not IsWindow(AWnd) then
    Exit;

  AWnd := GetAncestor(AWnd, GA_ROOT);
  if (AWnd = 0) or QSIsOwnProcessWindow(AWnd) then
    Exit;
  if IsIconic(AWnd) then
    Exit;

  R := QSGetWindowBounds(AWnd);
  W := R.Width;
  H := R.Height;
  if (W <= 0) or (H <= 0) then
    Exit;

  DIB := QSCreateTopDownDIB(W, H, Bits);
  if DIB = 0 then
    Exit;

  ScreenDC := GetDC(0);
  if ScreenDC = 0 then
  begin
    DeleteObject(DIB);
    Exit;
  end;

  MemDC := CreateCompatibleDC(ScreenDC);
  if MemDC = 0 then
  begin
    ReleaseDC(0, ScreenDC);
    DeleteObject(DIB);
    Exit;
  end;

  try
    Old := SelectObject(MemDC, DIB);
    if Old = 0 then
    begin
      DeleteObject(DIB);
      DIB := 0;
      Exit;
    end;

    try
      { PW_RENDERFULLCONTENT позволяет захватить содержимое окон,
        отрисовываемых через DirectComposition (Chrome, UWP и т.п.). }
      Ok := PrintWindow(AWnd, MemDC, PW_RENDERFULLCONTENT);
      if not Ok then
        Ok := PrintWindow(AWnd, MemDC, 0);

      if (not Ok) or QSDIBLooksEmpty(Bits, W, H) then
      begin
        { Запасной вариант: копируем видимую часть окна с экрана. }
        FillChar(Bits^, W * H * 4, 0);
        V := QSDesktopRect;
        Intersect := R;
        if IntersectRect(Intersect, Intersect, V) and
           (Intersect.Width > 0) and (Intersect.Height > 0) then
          BitBlt(MemDC, Intersect.Left - R.Left, Intersect.Top - R.Top,
            Intersect.Width, Intersect.Height,
            ScreenDC, Intersect.Left, Intersect.Top, SRCCOPY);
      end;

      GdiFlush;
    finally
      SelectObject(MemDC, Old);
    end;
  finally
    DeleteDC(MemDC);
    ReleaseDC(0, ScreenDC);
  end;

  try
    Result := QSBitmapFromDIB(DIB, Bits, W, H);
    if Result <> nil then
      ABounds := R;
  finally
    DeleteObject(DIB);
  end;
end;

function QSIsUsableAppWindow(AWnd: HWND): Boolean;
var
  Pid: DWORD;
  Cloaked: DWORD;
  ExStyle: NativeInt;
  ClsName: string;
  ClsLen: Integer;
begin
  Result := False;
  if (AWnd = 0) or not IsWindowVisible(AWnd) or IsIconic(AWnd) then
    Exit;
  if AWnd = GetShellWindow then
    Exit;
  if QSIsOwnProcessWindow(AWnd) then
    Exit;

  { GetClassName не завершает строку нулём, если буфер слишком мал,
    поэтому читаем в string ровно столько символов, сколько вернула
    функция. Сравнение с array[0..255] of Char дало бы строку с
    нулевыми символами в конце и никогда не совпало бы с именами. }
  SetLength(ClsName, 256);
  ClsLen := GetClassName(AWnd, PChar(ClsName), Length(ClsName));
  if ClsLen > 0 then
    SetLength(ClsName, ClsLen)
  else
    ClsName := '';

  if SameText(ClsName, 'Progman') or
     SameText(ClsName, 'WorkerW') or
     SameText(ClsName, 'Shell_TrayWnd') or
     SameText(ClsName, 'Windows.UI.Core.CoreWindow') then
    Exit;

  ExStyle := GetWindowLongPtr(AWnd, GWL_EXSTYLE);
  if (ExStyle and WS_EX_TOOLWINDOW) <> 0 then
    Exit;

  Cloaked := 0;
  if DwmGetWindowAttribute(AWnd, DWMWA_CLOAKED, @Cloaked, SizeOf(Cloaked)) = S_OK then
    if Cloaked <> 0 then
      Exit;

  if GetWindowTextLength(AWnd) = 0 then
    Exit;

  Pid := 0;
  GetWindowThreadProcessId(AWnd, Pid);
  Result := Pid <> 0;
end;

function QSForegroundAppWindow: HWND;
var
  H: HWND;
begin
  Result := 0;

  H := GetForegroundWindow;
  if QSIsUsableAppWindow(H) then
    Exit(H);

  { Наше окно было на переднем плане (например, нажата кнопка).
    Берём первое подходящее окно из Z-порядка. }
  H := GetTopWindow(0);
  while H <> 0 do
  begin
    if QSIsUsableAppWindow(H) then
      Exit(H);
    H := GetWindow(H, GW_HWNDNEXT);
  end;
end;

function QSCaptureForegroundWindow(out ABounds: TRect): TBitmap;
var
  H: HWND;
begin
  ABounds := Rect(0, 0, 0, 0);
  H := QSForegroundAppWindow;
  if H = 0 then
    Exit(nil);
  Result := QSCaptureWindow(H, ABounds);
end;

{ ------------------------------------------------------------------ }
{ Сохранение и буфер обмена                                          }
{ ------------------------------------------------------------------ }

function QSSaveBitmap(ABitmap: TBitmap; const AFileName: string;
  AQuality: Integer): Boolean;
var
  Ext, Dir: string;
  Params: TBitmapCodecSaveParams;
begin
  Result := False;
  if (ABitmap = nil) or ABitmap.IsEmpty or (AFileName = '') then
    Exit;

  Ext := LowerCase(ExtractFileExt(AFileName));
  if (Ext <> '.png') and (Ext <> '.jpg') and (Ext <> '.jpeg') then
    Exit;

  Dir := ExtractFileDir(AFileName);
  if (Dir <> '') and not DirectoryExists(Dir) then
    ForceDirectories(Dir);

  try
    if Ext = '.png' then
      ABitmap.SaveToFile(AFileName)
    else
    begin
      Params.Quality := EnsureRange(AQuality, 1, 100);
      ABitmap.SaveToFile(AFileName, @Params);
    end;
    Result := True;
  except
    Result := False;
  end;
end;

function QSCopyBitmapToClipboard(ABitmap: TBitmap): Boolean;
var
  Data: TBitmapData;
  W, H, X, Y, HeaderSize, ImageSize: Integer;
  DIBMem, PNGMem: HGLOBAL;
  P, Src: PByte;
  R, G, B: Byte;
  C: TAlphaColor;
  BI: TBitmapInfoHeader;
  PNGStream: TMemoryStream;
  PNGFormat: UINT;
  HasDIB, HasPNG: Boolean;

  function AllocGlobal(ASize: NativeInt; out AHandle: HGLOBAL;
    out APtr: PByte): Boolean;
  begin
    Result := False;
    APtr := nil;
    AHandle := GlobalAlloc(GMEM_MOVEABLE, ASize);
    if AHandle = 0 then
      Exit;
    APtr := GlobalLock(AHandle);
    if APtr = nil then
    begin
      GlobalFree(AHandle);
      AHandle := 0;
      Exit;
    end;
    Result := True;
  end;

begin
  Result := False;
  if (ABitmap = nil) or ABitmap.IsEmpty then
    Exit;

  W := ABitmap.Width;
  H := ABitmap.Height;
  HeaderSize := SizeOf(TBitmapInfoHeader);
  ImageSize := W * H * 4;

  DIBMem := 0;
  PNGMem := 0;
  PNGStream := nil;
  PNGFormat := 0;

  { ---------- CF_DIB ---------- }
  if not ABitmap.Map(TMapAccess.Read, Data) then
    Exit;
  try
    if AllocGlobal(HeaderSize + ImageSize, DIBMem, P) then
    begin
      FillChar(BI, SizeOf(BI), 0);
      BI.biSize := SizeOf(TBitmapInfoHeader);
      BI.biWidth := W;
      BI.biHeight := -H; { top-down }
      BI.biPlanes := 1;
      BI.biBitCount := 32;
      BI.biCompression := BI_RGB;
      BI.biSizeImage := ImageSize;
      Move(BI, P^, HeaderSize);

      for Y := 0 to H - 1 do
      begin
        Src := PByte(Data.Data) + NativeInt(Y) * Data.Pitch;
        for X := 0 to W - 1 do
        begin
          case Data.PixelFormat of
            TPixelFormat.BGRA:
              begin
                B := Src[X * 4 + 0];
                G := Src[X * 4 + 1];
                R := Src[X * 4 + 2];
              end;
            TPixelFormat.RGBA:
              begin
                R := Src[X * 4 + 0];
                G := Src[X * 4 + 1];
                B := Src[X * 4 + 2];
              end;
          else
            begin
              C := Data.GetPixel(X, Y);
              R := (C shr 16) and $FF;
              G := (C shr 8) and $FF;
              B := C and $FF;
            end;
          end;
          P[HeaderSize + Y * W * 4 + X * 4 + 0] := B;
          P[HeaderSize + Y * W * 4 + X * 4 + 1] := G;
          P[HeaderSize + Y * W * 4 + X * 4 + 2] := R;
          P[HeaderSize + Y * W * 4 + X * 4 + 3] := $FF;
        end;
      end;
      GlobalUnlock(DIBMem);
    end;
  finally
    ABitmap.Unmap(Data);
  end;

  { ---------- PNG ---------- }
  PNGFormat := RegisterClipboardFormat('PNG');
  if PNGFormat <> 0 then
  begin
    PNGStream := TMemoryStream.Create;
    try
      ABitmap.SaveToStream(PNGStream);
      if PNGStream.Size > 0 then
      begin
        PNGStream.Position := 0;
        if AllocGlobal(PNGStream.Size, PNGMem, P) then
        begin
          PNGStream.ReadBuffer(P^, PNGStream.Size);
          GlobalUnlock(PNGMem);
        end;
      end;
    finally
      PNGStream.Free;
    end;
  end;

  { Кладём оба формата за одно открытие буфера, иначе EmptyClipboard
    во втором проходе уничтожил бы первый формат. }
  HasDIB := False;
  HasPNG := False;
  if OpenClipboard(0) then
  try
    EmptyClipboard;

    if DIBMem <> 0 then
      if SetClipboardData(CF_DIB, DIBMem) <> 0 then
      begin
        HasDIB := True;
        DIBMem := 0;
      end;

    if (PNGFormat <> 0) and (PNGMem <> 0) then
      if SetClipboardData(PNGFormat, PNGMem) <> 0 then
      begin
        HasPNG := True;
        PNGMem := 0;
      end;
  finally
    CloseClipboard;
  end;

  if DIBMem <> 0 then
    GlobalFree(DIBMem);
  if PNGMem <> 0 then
    GlobalFree(PNGMem);

  Result := HasDIB or HasPNG;
end;

{ ------------------------------------------------------------------ }
{ Размытие                                                           }
{ ------------------------------------------------------------------ }

procedure QSBoxBlurHorizontal(const ASrc, ADst: TArray<Cardinal>;
  AWidth, AHeight, ARadius: Integer);
var
  X, Y, K, Count, Idx, C: Integer;
  SumR, SumG, SumB: Integer;
begin
  Count := ARadius * 2 + 1;
  for Y := 0 to AHeight - 1 do
  begin
    SumR := 0;
    SumG := 0;
    SumB := 0;

    for K := -ARadius to ARadius do
    begin
      Idx := Y * AWidth + EnsureRange(K, 0, AWidth - 1);
      C := Integer(ASrc[Idx]);
      Inc(SumB, C and $FF);
      Inc(SumG, (C shr 8) and $FF);
      Inc(SumR, (C shr 16) and $FF);
    end;

    for X := 0 to AWidth - 1 do
    begin
      C := Integer(ASrc[Y * AWidth + X]);
      ADst[Y * AWidth + X] :=
        (Cardinal(C) and $FF000000) or
        (Cardinal(SumR div Count) shl 16) or
        (Cardinal(SumG div Count) shl 8) or
        Cardinal(SumB div Count);

      if X < AWidth - 1 then
      begin
        Idx := Y * AWidth + Min(X + ARadius + 1, AWidth - 1);
        C := Integer(ASrc[Idx]);
        Inc(SumB, C and $FF);
        Inc(SumG, (C shr 8) and $FF);
        Inc(SumR, (C shr 16) and $FF);

        Idx := Y * AWidth + Max(X - ARadius, 0);
        C := Integer(ASrc[Idx]);
        Dec(SumB, C and $FF);
        Dec(SumG, (C shr 8) and $FF);
        Dec(SumR, (C shr 16) and $FF);
      end;
    end;
  end;
end;

procedure QSBoxBlurVertical(const ASrc, ADst: TArray<Cardinal>;
  AWidth, AHeight, ARadius: Integer);
var
  X, Y, K, Count, Idx, C: Integer;
  SumR, SumG, SumB: Integer;
begin
  Count := ARadius * 2 + 1;
  for X := 0 to AWidth - 1 do
  begin
    SumR := 0;
    SumG := 0;
    SumB := 0;

    for K := -ARadius to ARadius do
    begin
      Idx := EnsureRange(K, 0, AHeight - 1) * AWidth + X;
      C := Integer(ASrc[Idx]);
      Inc(SumB, C and $FF);
      Inc(SumG, (C shr 8) and $FF);
      Inc(SumR, (C shr 16) and $FF);
    end;

    for Y := 0 to AHeight - 1 do
    begin
      C := Integer(ASrc[Y * AWidth + X]);
      ADst[Y * AWidth + X] :=
        (Cardinal(C) and $FF000000) or
        (Cardinal(SumR div Count) shl 16) or
        (Cardinal(SumG div Count) shl 8) or
        Cardinal(SumB div Count);

      if Y < AHeight - 1 then
      begin
        Idx := Min(Y + ARadius + 1, AHeight - 1) * AWidth + X;
        C := Integer(ASrc[Idx]);
        Inc(SumB, C and $FF);
        Inc(SumG, (C shr 8) and $FF);
        Inc(SumR, (C shr 16) and $FF);

        Idx := Max(Y - ARadius, 0) * AWidth + X;
        C := Integer(ASrc[Idx]);
        Dec(SumB, C and $FF);
        Dec(SumG, (C shr 8) and $FF);
        Dec(SumR, (C shr 16) and $FF);
      end;
    end;
  end;
end;

procedure QSBlurBitmap(ABitmap: TBitmap; const ARect: TRect; ARadius: Integer);
var
  R: TRect;
  W, H, X, Y, Pass: Integer;
  Data: TBitmapData;
  Src, Dst: TArray<Cardinal>;
  P: PByte;
begin
  if (ABitmap = nil) or ABitmap.IsEmpty then
    Exit;

  R := ARect;
  R.NormalizeRect;
  if not IntersectRect(R, R, Rect(0, 0, ABitmap.Width, ABitmap.Height)) then
    Exit;

  W := R.Width;
  H := R.Height;
  if (W < 3) or (H < 3) then
    Exit;

  ARadius := EnsureRange(ARadius, 1, Max(1, Min(80, Max(W, H) div 2)));
  if (ARadius < 1) then
    Exit;

  if not ABitmap.Map(TMapAccess.ReadWrite, Data) then
    Exit;

  try
    if Data.BytesPerPixel <> 4 then
      Exit;

    SetLength(Src, W * H);
    SetLength(Dst, W * H);

    for Y := 0 to H - 1 do
    begin
      P := PByte(Data.GetPixelAddr(R.Left, R.Top + Y));
      Move(P^, Src[Y * W], W * 4);
      for X := 0 to W - 1 do
        Src[Y * W + X] := Src[Y * W + X] or $FF000000;
    end;

    { Три прохода дают мягкое размытие, близкое к гауссовому. }
    for Pass := 1 to 3 do
    begin
      QSBoxBlurHorizontal(Src, Dst, W, H, ARadius);
      QSBoxBlurVertical(Dst, Src, W, H, ARadius);
    end;

    for Y := 0 to H - 1 do
    begin
      P := PByte(Data.GetPixelAddr(R.Left, R.Top + Y));
      Move(Src[Y * W], P^, W * 4);
    end;
  finally
    ABitmap.Unmap(Data);
  end;
end;

{ ------------------------------------------------------------------ }
{ DPI                                                                }
{ ------------------------------------------------------------------ }

procedure QSEnableDpiAwareness;
var
  User32: HMODULE;
  Proc: TSetProcessDpiAwarenessContextProc;
begin
  User32 := GetModuleHandle('user32.dll');
  if User32 = 0 then
    Exit;

  @Proc := GetProcAddress(User32, 'SetProcessDpiAwarenessContext');
  if Assigned(Proc) then
  try
    { Если манифест уже задал Per-Monitor V2, вызов просто вернёт False. }
    Proc(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  except
    { На старых ОС функции может не быть - это не критично. }
  end;
end;

initialization
  QSEnableDpiAwareness;

end.
