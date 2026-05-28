unit FMX.Trayicon.Win;

interface

{$IFNDEF MSWINDOWS}
  {$HINTS OFF}
{$ENDIF}

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
{$IFDEF MSWINDOWS}
  Winapi.ShellAPI, Winapi.Windows, Winapi.Messages, Winapi.MultiMon,
{$ENDIF}
  FMX.Dialogs, FMX.Menus, FMX.Forms, FMX.Objects, System.Messaging,
  FMX.Platform.Win, FMX.Graphics,  FMX.Platform;

{$IFDEF MSWINDOWS}
const
  WM_TRAYICON = WM_USER + 1;
  NIF_SHOWTIP   = $00000080;
  NIN_POPUPOPEN  = $406;
  NIN_POPUPCLOSE = $407;
{$ENDIF}

type
  TBalloonIconType = (None, Info, Warning, Error, User, BigWarning, BigError);

{$IFNDEF MSWINDOWS}
  HICON = Int64;
  LONG_PTR = Integer;
  HWND = Integer;

  TNotifyIconData = record
  end;
{$ENDIF}

type
  TIcon = HICON;

  TTrayIconNotify = procedure(ID: Integer) of object;

  [ComponentPlatformsAttribute(pidWin32 or pidWin64 or pidWinNX32 or pidWinARM32)]
  TFMXTrayIcon = class(TComponent)
    type
      TTrayList = class(TList<TFMXTrayIcon>)
        procedure Delete(TrayIcon: TFMXTrayIcon); overload;
        function GetByID(ID: Integer; var TrayIcon: TFMXTrayIcon): Boolean;
      end;
  private
    class var
      TrayList: TTrayList;
      IDs: Integer;
      NeedHook: Boolean;
      OldWndProc: LONG_PTR;
      FIsWin11: Boolean;
  private
    FIcon: TIcon;
    FFMXIcon: TBitmap;
    FHICON: HICON;
    FHint: string;
    FBalloonTitle: string;
    FBalloonText: string;
    FBalloonIconType: TBalloonIconType;
    FNotifyIconData: TNotifyIconData;
    FPopupMenu: TPopupMenu;
    FPopupOffset: Integer;
    FOnClick: TNotifyEvent;
    FOnDblClick: TNotifyEvent;
    FOnPopup: TNotifyEvent;
    FShowing: Boolean;
    FAutoShow: Boolean;
    FID: Integer;
    FIconResource: string;
    FShowingPopup: Boolean;
    FTooltipWnd: HWND;
    procedure DoOnClick;
    procedure DoOnDblClick;
    procedure DoOnRightClick;
    procedure DoOnPopup;
    procedure SetAutoShow(const Value: Boolean);
    class procedure Hook(Handle: HWND);
    class procedure InternalTrayIconClick(ID: Integer);
    class procedure InternalTrayIconDblClick(ID: Integer);
    class procedure InternalTrayIconRightClick(ID: Integer);
    class procedure InternalTrayIconPopupOpen(ID: Integer);
    class procedure InternalTrayIconPopupClose(ID: Integer);
    procedure SetID(const Value: Integer);
    procedure SetIcon(const Value: TIcon);
    procedure UpdateIcon;
    procedure SetHint(const Value: string);
    procedure UpdateHint;
    procedure SetIconResource(const Value: string);
    function GetWindowHandle: HWND;
    procedure SetPopupMenu(const Value: TPopupMenu);
    procedure FOnPopupForm(const Sender: TObject; const M: TMessage);
    procedure ShowCustomTooltip;
    procedure HideCustomTooltip;
    procedure LoadIconFromBitmapInternal(Bitmap: TBitmap);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Show;
    procedure Hide;
    procedure RecreateIcon(Rehook: Boolean = False);
    procedure ShowBalloonHint; overload;
    procedure ShowBalloonHint(Title, Text: string; BalloonIcon: TBalloonIconType); overload;
    property Icon: TIcon read FIcon write SetIcon;
    procedure LoadIconFromResources(ResourceName: string);
    procedure LoadIconFromBitmapStream(Stream: TStream);
    property WindowHandle: HWND read GetWindowHandle;
  protected
    procedure Loaded; override;
  published
    property Hint: string read FHint write SetHint;
    property BalloonText: string read FBalloonText write FBalloonText;
    property BalloonTitle: string read FBalloonTitle write FBalloonTitle;
    property BalloonIconType: TBalloonIconType read FBalloonIconType write FBalloonIconType default TBalloonIconType.None;
    property PopupOffset: Integer read FPopupOffset write FPopupOffset default 0;
    property PopupMenu: TPopupMenu read FPopupMenu write SetPopupMenu;
    property AutoShow: Boolean read FAutoShow write SetAutoShow default True;
    property ID: Integer read FID write SetID;
    property OnClick: TNotifyEvent read FOnClick write FOnClick;
    property OnDblClick: TNotifyEvent read FOnDblClick write FOnDblClick;
    property OnPopup: TNotifyEvent read FOnPopup write FOnPopup;
    property IconResource: string read FIconResource write SetIconResource;
  end;

procedure Register;

implementation

uses
  System.Types, FMX.Types, FMX.Controls, System.UITypes;

procedure Register;
begin
  RegisterComponents('Win32', [TFMXTrayIcon]);
end;

{$IFDEF MSWINDOWS}

const
  TOOLTIP_CLASSNAME = 'FMXTrayIconTooltip';
  TOOLTIP_PADDING   = 8;
  TOOLTIP_MAX_WIDTH = 400;

function TooltipWndProc(Wnd: HWND; Msg: UINT; WParam: WParam; LParam: LParam): LRESULT; stdcall;
var
  PS: TPaintStruct;
  DC: HDC;
  R, TextR: TRect;
  Text: array[0..1023] of WideChar;
  TextLen: Integer;
  OldFont: HFONT;
  Font: HFONT;
  NcMetrics: TNonClientMetrics;
begin
  case Msg of
    WM_PAINT:
    begin
      DC := BeginPaint(Wnd, PS);
      try
        GetClientRect(Wnd, R);
        SetBkMode(DC, TRANSPARENT);
        FillRect(DC, R, GetSysColorBrush(COLOR_INFOBK));
        FrameRect(DC, R, GetSysColorBrush(COLOR_WINDOWFRAME));

        NcMetrics.cbSize := SizeOf(NcMetrics);
        if SystemParametersInfo(SPI_GETNONCLIENTMETRICS, SizeOf(NcMetrics), @NcMetrics, 0) then
          Font := CreateFontIndirect(NcMetrics.lfStatusFont)
        else
          Font := GetStockObject(DEFAULT_GUI_FONT);
        OldFont := SelectObject(DC, Font);
        SetTextColor(DC, GetSysColor(COLOR_INFOTEXT));

        TextR := Rect(R.Left + TOOLTIP_PADDING, R.Top + TOOLTIP_PADDING,
                      R.Right - TOOLTIP_PADDING, R.Bottom - TOOLTIP_PADDING);
        TextLen := GetWindowTextW(Wnd, Text, Length(Text));
        DrawTextW(DC, Text, TextLen, TextR, DT_LEFT or DT_WORDBREAK or DT_NOPREFIX);
        SelectObject(DC, OldFont);
        if NcMetrics.cbSize > 0 then
          DeleteObject(Font);
      finally
        EndPaint(Wnd, PS);
      end;
      Result := 0;
    end;
    WM_ERASEBKGND:
      Result := 1;
  else
    Result := DefWindowProc(Wnd, Msg, WParam, LParam);
  end;
end;

procedure EnsureTooltipClass;
var
  WC: TWndClassEx;
begin
  if GetClassInfoEx(hInstance, TOOLTIP_CLASSNAME, WC) then
    Exit;
  FillChar(WC, SizeOf(WC), 0);
  WC.cbSize      := SizeOf(WC);
  WC.style       := CS_HREDRAW or CS_VREDRAW;
  WC.lpfnWndProc := @TooltipWndProc;
  WC.hInstance   := hInstance;
  WC.hCursor     := LoadCursor(0, IDC_ARROW);
  WC.hbrBackground := 0;
  WC.lpszClassName := TOOLTIP_CLASSNAME;
  RegisterClassEx(WC);
end;

function HookWndProc(HWND: HWND; Msg: UINT; WParam: WParam; LParam: LParam): LRESULT; stdcall;
var
  Event: Word;
  IconID: Word;
begin
  try
    if Msg = WM_TRAYICON then
    begin
      Event  := LParam and $FFFF;
      IconID := (LParam shr 16) and $FFFF;
      case Event of
        WM_LBUTTONDBLCLK:
          TFMXTrayIcon.InternalTrayIconDblClick(IconID);
        WM_LBUTTONUP:
          TFMXTrayIcon.InternalTrayIconClick(IconID);
        WM_RBUTTONUP:
          TFMXTrayIcon.InternalTrayIconRightClick(IconID);
        NIN_POPUPOPEN:
          TFMXTrayIcon.InternalTrayIconPopupOpen(IconID);
        NIN_POPUPCLOSE:
          TFMXTrayIcon.InternalTrayIconPopupClose(IconID);
      end;
    end;
  except
  end;
  Result := CallWindowProc(Ptr(TFMXTrayIcon.OldWndProc), HWND, Msg, WParam, LParam);
end;


type
  TLongWordArray = array[0..32767] of LongWord;
  PLongWordArray = ^TLongWordArray;

function BitmapToHICON(Bitmap: TBitmap): HICON;
var
  IconInfo: TIconInfo;
  hbmColor, hbmMask: HBITMAP;
  BitmapData: TBitmapData;
  x, y: Integer;
  DC, ColorDC, MaskDC: HDC;
  OldColorBmp, OldMaskBmp: HGDIOBJ;
begin
  Result := 0;
  if (Bitmap = nil) or (Bitmap.Width = 0) or (Bitmap.Height = 0) then
    Exit;

  hbmColor := CreateBitmap(Bitmap.Width, Bitmap.Height, 1, 32, nil);
  hbmMask := CreateBitmap(Bitmap.Width, Bitmap.Height, 1, 1, nil);

  if (hbmColor = 0) or (hbmMask = 0) then
  begin
    if hbmColor <> 0 then DeleteObject(hbmColor);
    if hbmMask <> 0 then DeleteObject(hbmMask);
    Exit;
  end;

  DC := GetDC(0);
  try
    ColorDC := CreateCompatibleDC(DC);
    MaskDC := CreateCompatibleDC(DC);
    try
      OldColorBmp := SelectObject(ColorDC, hbmColor);
      OldMaskBmp := SelectObject(MaskDC, hbmMask);

      PatBlt(ColorDC, 0, 0, Bitmap.Width, Bitmap.Height, BLACKNESS);
      PatBlt(MaskDC, 0, 0, Bitmap.Width, Bitmap.Height, WHITENESS); // По умолчанию все непрозрачно

      if Bitmap.Map(TMapAccess.Read, BitmapData) then
      try
        for y := 0 to Bitmap.Height - 1 do
        begin
          for x := 0 to Bitmap.Width - 1 do
          begin
            var Pixel := BitmapData.GetPixel(x, y);
            var R := TAlphaColorRec(Pixel).R;
            var G := TAlphaColorRec(Pixel).G;
            var B := TAlphaColorRec(Pixel).B;
            var A := TAlphaColorRec(Pixel).A;

            SetPixelV(ColorDC, x, y, RGB(R, G, B));

            // Для маски: белый = прозрачный, черный = непрозрачный
            if A < 128 then
              SetPixelV(MaskDC, x, y, RGB(255, 255, 255))  // Прозрачный
            else
              SetPixelV(MaskDC, x, y, RGB(0, 0, 0));       // Непрозрачный
          end;
        end;
      finally
        Bitmap.Unmap(BitmapData);
      end;

      SelectObject(ColorDC, OldColorBmp);
      SelectObject(MaskDC, OldMaskBmp);

    finally
      DeleteDC(ColorDC);
      DeleteDC(MaskDC);
    end;
  finally
    ReleaseDC(0, DC);
  end;

  FillChar(IconInfo, SizeOf(IconInfo), 0);
  IconInfo.fIcon := True;
  IconInfo.hbmColor := hbmColor;
  IconInfo.hbmMask := hbmMask;

  Result := CreateIconIndirect(IconInfo);

  if Result = 0 then
  begin
    DeleteObject(hbmColor);
    DeleteObject(hbmMask);
  end;
end;
{$ENDIF}

class procedure TFMXTrayIcon.Hook;
begin
{$IFDEF MSWINDOWS}
  if NeedHook then
  begin
    OldWndProc := GetWindowLongPtr(Handle, GWL_WNDPROC);
    SetWindowLongPtr(Handle, GWL_WNDPROC, LONG_PTR(@HookWndProc));
    NeedHook := False;
  end;
{$ENDIF}
end;

class procedure TFMXTrayIcon.InternalTrayIconClick(ID: Integer);
var
  Tray: TFMXTrayIcon;
begin
  if TrayList.GetByID(ID, Tray) then
    Tray.DoOnClick;
end;

class procedure TFMXTrayIcon.InternalTrayIconDblClick(ID: Integer);
var
  Tray: TFMXTrayIcon;
begin
  if TrayList.GetByID(ID, Tray) then
    Tray.DoOnDblClick;
end;

class procedure TFMXTrayIcon.InternalTrayIconRightClick(ID: Integer);
var
  Tray: TFMXTrayIcon;
begin
  if TrayList.GetByID(ID, Tray) then
    Tray.DoOnRightClick;
end;

class procedure TFMXTrayIcon.InternalTrayIconPopupOpen(ID: Integer);
var
  Tray: TFMXTrayIcon;
begin
  if TrayList.GetByID(ID, Tray) then
    Tray.ShowCustomTooltip;
end;

class procedure TFMXTrayIcon.InternalTrayIconPopupClose(ID: Integer);
var
  Tray: TFMXTrayIcon;
begin
  if TrayList.GetByID(ID, Tray) then
    Tray.HideCustomTooltip;
end;

constructor TFMXTrayIcon.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FShowingPopup := False;
  TMessageManager.DefaultManager.SubscribeToMessage(TFormBeforeShownMessage, FOnPopupForm);
  Inc(IDs);
  FID := IDs;
  FShowing := False;
  FAutoShow := True;
  FPopupOffset := 0;
{$IFDEF MSWINDOWS}
  FHICON := GetClassLong(WindowHandle, GCL_HICONSM);
  FTooltipWnd := 0;
{$ENDIF}
  TrayList.Add(Self);
end;

procedure TFMXTrayIcon.SetAutoShow(const Value: Boolean);
begin
  FAutoShow := Value;
end;

procedure TFMXTrayIcon.SetHint(const Value: string);
begin
  FHint := Value;
  if FShowing then
    UpdateHint;
end;


procedure TFMXTrayIcon.SetIcon(const Value: TIcon);
begin
  FIcon := Value;
{$IFDEF MSWINDOWS}
  if FIcon <> 0 then
    FHICON := FIcon
  else
    FHICON := GetClassLong(WindowHandle, GCL_HICONSM);
  if FShowing then
    UpdateIcon;
{$ENDIF}
end;

procedure TFMXTrayIcon.SetIconResource(const Value: string);
begin
  FIconResource := Value;
  LoadIconFromResources(Value);
end;

procedure TFMXTrayIcon.SetID(const Value: Integer);
begin
  FID := Value;
end;

procedure TFMXTrayIcon.SetPopupMenu(const Value: TPopupMenu);
begin
  FPopupMenu := Value;
end;

procedure TFMXTrayIcon.RecreateIcon;
begin
{$IFDEF MSWINDOWS}
  if Rehook then
    TFMXTrayIcon.NeedHook := True;

  FShowing := True;
  FNotifyIconData.cbSize := SizeOf(FNotifyIconData);
  FNotifyIconData.Wnd := WindowHandle;
  FNotifyIconData.uID := FID;
  FNotifyIconData.uCallbackMessage := WM_TRAYICON;
  FNotifyIconData.hIcon := FHICON;
  FNotifyIconData.dwInfoFlags := NIIF_NONE;

  if (Length(FHint) > 127) and (not FIsWin11) then begin
    FNotifyIconData.uFlags := NIF_MESSAGE + NIF_ICON + NIF_TIP;
  end else begin
    FNotifyIconData.uFlags := NIF_MESSAGE + NIF_ICON + NIF_TIP + NIF_SHOWTIP;
  end;
  StrLCopy(FNotifyIconData.szTip, PChar(FHint), High(FNotifyIconData.szTip));

  Shell_NotifyIcon(NIM_ADD, @FNotifyIconData);

  FNotifyIconData.uVersion := NOTIFYICON_VERSION_4;
  Shell_NotifyIcon(NIM_SETVERSION, @FNotifyIconData);

  if Owner is TForm then
    Hook(WindowHandle);
{$ENDIF}
end;

procedure TFMXTrayIcon.Show;
begin
{$IFDEF MSWINDOWS}
  if FShowing then
    Exit;
  RecreateIcon;
{$ENDIF}
end;

procedure TFMXTrayIcon.ShowBalloonHint;
begin
{$IFDEF MSWINDOWS}
  StrLCopy(FNotifyIconData.szInfo, PChar(FBalloonText), High(FNotifyIconData.szInfo));
  StrLCopy(FNotifyIconData.szInfoTitle, PChar(FBalloonTitle), High(FNotifyIconData.szInfoTitle));
  FNotifyIconData.dwInfoFlags := Ord(FBalloonIconType);
  FNotifyIconData.uFlags := NIF_INFO;
  Shell_NotifyIcon(NIM_MODIFY, @FNotifyIconData);
{$ENDIF}
end;

procedure TFMXTrayIcon.ShowBalloonHint(Title, Text: string; BalloonIcon: TBalloonIconType);
begin
  FBalloonText := Text;
  FBalloonTitle := Title;
  FBalloonIconType := BalloonIcon;
  ShowBalloonHint;
end;

procedure TFMXTrayIcon.UpdateIcon;
begin
{$IFDEF MSWINDOWS}
  FNotifyIconData.hIcon := FHICON;
  FNotifyIconData.uFlags := NIF_ICON;
  Shell_NotifyIcon(NIM_MODIFY, @FNotifyIconData);
{$ENDIF}
end;

procedure TFMXTrayIcon.UpdateHint;
begin
{$IFDEF MSWINDOWS}
  if (Length(FHint) > 127) and (not FIsWin11) then begin
    FNotifyIconData.uFlags := NIF_TIP;
  end else begin
    FNotifyIconData.uFlags := NIF_TIP + NIF_SHOWTIP;
  end;
  StrLCopy(FNotifyIconData.szTip, PChar(FHint), High(FNotifyIconData.szTip));
  Shell_NotifyIcon(NIM_MODIFY, @FNotifyIconData);
{$ENDIF}
end;

procedure TFMXTrayIcon.Hide;
begin
  HideCustomTooltip;
  FShowing := False;
{$IFDEF MSWINDOWS}
  Shell_NotifyIcon(NIM_DELETE, @FNotifyIconData);
{$ENDIF}
end;

procedure TFMXTrayIcon.Loaded;
begin
  inherited;
  if not (csDesigning in ComponentState) then
  begin
    if FAutoShow then
      Show;
  end;
end;

procedure TFMXTrayIcon.LoadIconFromBitmapInternal(Bitmap: TBitmap);
{$IFDEF MSWINDOWS}
begin
  if Bitmap = nil then
    Exit;

  FFMXIcon := Bitmap;
  FHICON := BitmapToHICON(Bitmap);

  if FHICON = 0 then
    FHICON := GetClassLong(GetWindowHandle, GCL_HICONSM);

  if FShowing then begin
    FNotifyIconData.hIcon := FHICON;
    FNotifyIconData.uFlags := NIF_ICON;
    Shell_NotifyIcon(NIM_MODIFY, @FNotifyIconData);
  end;
{$ELSE}
begin
{$ENDIF}
end;

procedure TFMXTrayIcon.LoadIconFromBitmapStream(Stream: TStream);
{$IFDEF MSWINDOWS}
var
  Bitmap: TBitmap;
begin
  Bitmap := TBitmap.Create;
  try
    Bitmap.LoadFromStream(Stream);
    LoadIconFromBitmapInternal(Bitmap);
  finally
    Bitmap.Free;
  end;
{$ELSE}
begin
{$ENDIF}
end;

procedure TFMXTrayIcon.LoadIconFromResources(ResourceName: string);
begin
{$IFDEF MSWINDOWS}
  FHICON := LoadIcon(hInstance, PChar(ResourceName));
  if FHICON = 0 then
    FHICON := LoadIcon(0, PChar(ResourceName));
  FIcon := FHICON;
  if FShowing then
    UpdateIcon;
{$ENDIF}
end;

destructor TFMXTrayIcon.Destroy;
begin
  TMessageManager.DefaultManager.Unsubscribe(TFormBeforeShownMessage, FOnPopupForm);
  if FShowing then
    Hide;
  TrayList.Delete(Self);
{$IFDEF MSWINDOWS}
  HideCustomTooltip;
{$ENDIF}
  inherited;
end;

procedure TFMXTrayIcon.ShowCustomTooltip;
{$IFDEF MSWINDOWS}
var
  CurPos: TPoint;
  DC: HDC;
  TextR: TRect;
  WndW, WndH: Integer;
  MonInfo: TMonitorInfo;
  Mon: HMONITOR;
  NcMetrics: TNonClientMetrics;
  Font, OldFont: HFONT;
  Text: PChar;
begin
  if Length(FHint) <= 127 then
    Exit;

  EnsureTooltipClass;
  HideCustomTooltip;

  Text := PChar(FHint);

  DC := GetDC(0);
  try
    NcMetrics.cbSize := SizeOf(NcMetrics);
    if SystemParametersInfo(SPI_GETNONCLIENTMETRICS, SizeOf(NcMetrics), @NcMetrics, 0) then
      Font := CreateFontIndirect(NcMetrics.lfStatusFont)
    else
      Font := GetStockObject(DEFAULT_GUI_FONT);
    OldFont := SelectObject(DC, Font);
    TextR := Rect(0, 0, TOOLTIP_MAX_WIDTH - TOOLTIP_PADDING * 2, 0);
    DrawText(DC, Text, -1, TextR, DT_LEFT or DT_WORDBREAK or DT_NOPREFIX or DT_CALCRECT);
    SelectObject(DC, OldFont);
    if Font <> GetStockObject(DEFAULT_GUI_FONT) then
      DeleteObject(Font);
  finally
    ReleaseDC(0, DC);
  end;

  WndW := TextR.Right - TextR.Left + TOOLTIP_PADDING * 2;
  WndH := TextR.Bottom - TextR.Top + TOOLTIP_PADDING * 2;

  GetCursorPos(CurPos);
  Mon := MonitorFromPoint(CurPos, MONITOR_DEFAULTTONEAREST);
  MonInfo.cbSize := SizeOf(MonInfo);
  GetMonitorInfo(Mon, @MonInfo);

  CurPos.X := CurPos.X - WndW div 2;
  CurPos.Y := CurPos.Y - WndH - 4;

  if CurPos.X + WndW > MonInfo.rcWork.Right  then CurPos.X := MonInfo.rcWork.Right - WndW;
  if CurPos.X < MonInfo.rcWork.Left   then CurPos.X := MonInfo.rcWork.Left;
  if CurPos.Y < MonInfo.rcWork.Top    then CurPos.Y := MonInfo.rcWork.Top;

  FTooltipWnd := CreateWindowEx(
    WS_EX_TOPMOST or WS_EX_TOOLWINDOW or WS_EX_NOACTIVATE,
    TOOLTIP_CLASSNAME,
    Text,
    WS_POPUP,
    CurPos.X, CurPos.Y, WndW, WndH,
    0, 0, hInstance, nil);

  if FTooltipWnd <> 0 then
    ShowWindow(FTooltipWnd, SW_SHOWNOACTIVATE);
{$ELSE}
begin
{$ENDIF}
end;

procedure TFMXTrayIcon.HideCustomTooltip;
begin
{$IFDEF MSWINDOWS}
  if FTooltipWnd <> 0 then
  begin
    DestroyWindow(FTooltipWnd);
    FTooltipWnd := 0;
  end;
{$ENDIF}
end;

procedure TFMXTrayIcon.DoOnClick;
begin
  if Assigned(FOnClick) then
    FOnClick(Self);
end;

procedure TFMXTrayIcon.DoOnDblClick;
begin
  if Assigned(FOnDblClick) then
    FOnDblClick(Self);
end;

procedure TFMXTrayIcon.DoOnPopup;
{$IFDEF MSWINDOWS}
var
  CurPos: TPoint;
begin
  SetForegroundWindow(ApplicationHWND);
  GetCursorPos(CurPos);
  if Assigned(FPopupMenu) then
  begin
    FPopupMenu.CloseMenu;
    FShowingPopup := True;
    try
      FPopupMenu.Popup(CurPos.X, CurPos.Y - FPopupOffset);
    finally
      FShowingPopup := False;
    end;
  end;
{$ELSE}
begin
{$ENDIF}
end;

procedure TFMXTrayIcon.DoOnRightClick;
begin
  if Assigned(FOnPopup) then
    FOnPopup(Self)
  else
    DoOnPopup;
end;

procedure TFMXTrayIcon.FOnPopupForm(const Sender: TObject; const M: TMessage);
var
  Msg: TFormBeforeShownMessage absolute M;
begin
  if FShowingPopup and (Msg.Value is TCustomPopupForm) then
  begin
    SetWindowPos(
        FormToHWND(Msg.Value),
        HWND_TOPMOST, 0, 0, 0, 0,
        SWP_NOSIZE or SWP_NOMOVE or SWP_NOACTIVATE
    );
  end;
end;

function TFMXTrayIcon.GetWindowHandle: HWND;
begin
  Result := FmxHandleToHWND((Owner as TForm).Handle);
end;

{ TTrayIcon.TTrayList }

procedure TFMXTrayIcon.TTrayList.Delete(TrayIcon: TFMXTrayIcon);
var
  i: Integer;
begin
  for i := 0 to Self.Count - 1 do
    if Self[i] = TrayIcon then
    begin
      Self.Delete(i);
      Break;
    end;
end;

function TFMXTrayIcon.TTrayList.GetByID(ID: Integer; var TrayIcon: TFMXTrayIcon): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to Self.Count - 1 do
  begin
    if Self[i].ID = ID then
    begin
      Result := True;
      TrayIcon := Self[i];
      Exit;
    end;
  end;
end;

initialization
  TFMXTrayIcon.TrayList := TFMXTrayIcon.TTrayList.Create;
  TFMXTrayIcon.NeedHook := True;
  TFMXTrayIcon.IDs := 0;
{$IFDEF MSWINDOWS}
  TFMXTrayIcon.FIsWin11 := (TOSVersion.Major > 10) or
    ((TOSVersion.Major = 10) and (TOSVersion.Build >= 22000));
{$ELSE}
  TFMXTrayIcon.FIsWin11 := False;
{$ENDIF}

finalization
  TFMXTrayIcon.TrayList.Free;

end.

