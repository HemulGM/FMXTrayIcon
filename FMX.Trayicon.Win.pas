unit FMX.Trayicon.Win;

interface

{$IFNDEF MSWINDOWS}
  {$HINTS OFF}
{$ENDIF}
uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  {$IFDEF MSWINDOWS}
  FMX.Platform.Win, Winapi.ShellAPI, Winapi.Windows, Winapi.Messages,
  {$ENDIF}
  FMX.Dialogs, FMX.Menus, FMX.Forms, FMX.Objects;

{$IFDEF MSWINDOWS}
const
  WM_TRAYICON = WM_USER + 1;
{$ENDIF}

type
  TBalloonIconType = (None, Info, Warning, Error, User, BigWarning, BigError);

{$IFNDEF MSWINDOWS}
  HICON = Int64;

  LONG_PTR = Integer;

  TNotifyIconData = record
  end;

  HWND = Integer;
{$ENDIF}

type
  TIcon = HICON;

  TTrayIconNotify = procedure(ID: Integer) of object;

  TTrayIcon = class(TComponent)
    type
      TTrayList = class(TList<TTrayIcon>)
        procedure Delete(TrayIcon: TTrayIcon); overload;
        function GetByID(ID: Integer; var TrayIcon: TTrayIcon): Boolean;
      end;
  private
    class var
      TrayList: TTrayList;
      IDs: Integer;
      NeedHook: Boolean;
      OldWndProc: LONG_PTR;
  private
    FIcon: TIcon;
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
    FWindowHandle: HWND;
    FIconResource: string;
    procedure DoOnClick;
    procedure DoOnDblClick;
    procedure DoOnRightClick;
    procedure DoOnPopup;
    procedure SetAutoShow(const Value: Boolean);
    class procedure Hook(Handle: HWND);
    class procedure InternalTrayIconClick(ID: Integer);
    class procedure InternalTrayIconDblClick(ID: Integer);
    class procedure InternalTrayIconRightClick(ID: Integer);
    procedure SetID(const Value: Integer);
    procedure SetIcon(const Value: TIcon);
    procedure UpdateIcon;
    procedure SetHint(const Value: string);
    procedure UpdateHint;
    procedure SetIconResource(const Value: string);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Show;
    procedure Hide;
    procedure ShowBalloonHint; overload;
    procedure ShowBalloonHint(Title, Text: string; BalloonIcon: TBalloonIconType); overload;
    property Icon: TIcon read FIcon write SetIcon;
    procedure LoadIconFromResources(ResourceName: string);
  protected
    procedure Loaded; override;
  published
    property Hint: string read FHint write SetHint;
    property BalloonText: string read FBalloonText write FBalloonText;
    property BalloonTitle: string read FBalloonTitle write FBalloonTitle;
    property BalloonIconType: TBalloonIconType read FBalloonIconType write FBalloonIconType default TBalloonIconType.None;
    property PopupOffset: Integer read FPopupOffset write FPopupOffset default 0;
    property PopupMenu: TPopupMenu read FPopupMenu write FPopupMenu;
    property AutoShow: Boolean read FAutoShow write SetAutoShow default True;
    property ID: Integer read FID write SetID;
    property OnClick: TNotifyEvent read FOnClick write FOnClick;
    property OnDblClick: TNotifyEvent read FOnDblClick write FOnDblClick;
    property OnPopup: TNotifyEvent read FOnPopup write FOnPopup;
    property IconResource: string read FIconResource write SetIconResource;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('Win32', [TTrayIcon]);
end;

{$IFDEF MSWINDOWS}
function HookWndProc(HWND: HWND; Msg: UINT; WParam: WParam; LParam: LParam): LRESULT; stdcall;
begin
  try
    if Msg = WM_TRAYICON then
    begin
      case LParam of
        WM_LBUTTONDBLCLK:
          TTrayIcon.InternalTrayIconDblClick(WParam);
        WM_LBUTTONDOWN:
          TTrayIcon.InternalTrayIconClick(WParam);
        WM_RBUTTONDOWN:
          TTrayIcon.InternalTrayIconRightClick(WParam);
      end;
    end;
  except
  end;
  Result := CallWindowProc(Ptr(TTrayIcon.OldWndProc), HWND, Msg, WParam, LParam);
end;
{$ENDIF}

class procedure TTrayIcon.Hook;
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

class procedure TTrayIcon.InternalTrayIconClick(ID: Integer);
var
  Tray: TTrayIcon;
begin
  if TrayList.GetByID(ID, Tray) then
    Tray.DoOnClick;
end;

class procedure TTrayIcon.InternalTrayIconDblClick(ID: Integer);
var
  Tray: TTrayIcon;
begin
  if TrayList.GetByID(ID, Tray) then
    Tray.DoOnDblClick;
end;

class procedure TTrayIcon.InternalTrayIconRightClick(ID: Integer);
var
  Tray: TTrayIcon;
begin
  if TrayList.GetByID(ID, Tray) then
    Tray.DoOnRightClick;
end;

constructor TTrayIcon.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Inc(IDs);
  FID := IDs;
  FShowing := False;
  FAutoShow := True;
  FPopupOffset := 0;
  {$IFDEF MSWINDOWS}
  FWindowHandle := FmxHandleToHWND((Owner as TForm).Handle);
  FHICON := GetClassLong(FWindowHandle, GCL_HICONSM);
  {$ENDIF}
  //
  TrayList.Add(Self);
end;

procedure TTrayIcon.SetAutoShow(const Value: Boolean);
begin
  FAutoShow := Value;
end;

procedure TTrayIcon.SetHint(const Value: string);
begin
  FHint := Value;
  if FShowing then
    UpdateHint;
end;

procedure TTrayIcon.SetIcon(const Value: TIcon);
begin
  FIcon := Value;
  {$IFDEF MSWINDOWS}
  if FIcon <> 0 then
    FHICON := FIcon
  else
    FHICON := GetClassLong(FWindowHandle, GCL_HICONSM);
  if FShowing then
    UpdateIcon;
  {$ENDIF}
end;

procedure TTrayIcon.SetIconResource(const Value: string);
begin
  FIconResource := Value;
  LoadIconFromResources(Value);
end;

procedure TTrayIcon.SetID(const Value: Integer);
begin
  FID := Value;
end;

procedure TTrayIcon.Show;
begin
  {$IFDEF MSWINDOWS}
  if FShowing then
    Exit;
  FShowing := True;
  with FNotifyIconData do
  begin
    cbSize := SizeOf;
    Wnd := FWindowHandle;
    uID := FID;
    uFlags := NIF_MESSAGE + NIF_ICON + NIF_TIP;
    dwInfoFlags := NIIF_NONE;
    uCallbackMessage := WM_TRAYICON;
    hIcon := FHICON;
    StrLCopy(szTip, PChar(FHint), High(szTip));
  end;
  Shell_NotifyIcon(NIM_ADD, @FNotifyIconData);
  if Owner is TForm then
    Hook(FWindowHandle);
  {$ENDIF}
end;

procedure TTrayIcon.ShowBalloonHint;
begin
  {$IFDEF MSWINDOWS}
  with FNotifyIconData do
  begin
    StrLCopy(szInfo, PChar(FBalloonText), High(szInfo));
    StrLCopy(szInfoTitle, PChar(FBalloonTitle), High(szInfoTitle));
    dwInfoFlags := Ord(FBalloonIconType);
    uFlags := NIF_INFO;
  end;
  Shell_NotifyIcon(NIM_MODIFY, @FNotifyIconData);
  {$ENDIF}
end;

procedure TTrayIcon.ShowBalloonHint(Title, Text: string; BalloonIcon: TBalloonIconType);
begin
  FBalloonText := Text;
  FBalloonTitle := Title;
  FBalloonIconType := BalloonIcon;
  ShowBalloonHint;
end;

procedure TTrayIcon.UpdateIcon;
begin
  {$IFDEF MSWINDOWS}
  with FNotifyIconData do
  begin
    hIcon := FHICON;
    uFlags := NIF_ICON;
  end;
  Shell_NotifyIcon(NIM_MODIFY, @FNotifyIconData);
  {$ENDIF}
end;

procedure TTrayIcon.UpdateHint;
begin
  {$IFDEF MSWINDOWS}
  with FNotifyIconData do
  begin
    StrLCopy(szTip, PChar(FHint), High(szTip));
    uFlags := NIF_TIP;
  end;
  Shell_NotifyIcon(NIM_MODIFY, @FNotifyIconData);
  {$ENDIF}
end;

procedure TTrayIcon.Hide;
begin
  FShowing := False;
  {$IFDEF MSWINDOWS}
  Shell_NotifyIcon(NIM_DELETE, @FNotifyIconData);
  {$ENDIF}
end;

procedure TTrayIcon.Loaded;
begin
  inherited;
  if not (csDesigning in ComponentState) then
  begin
    if FAutoShow then
      Show;
  end;
end;

procedure TTrayIcon.LoadIconFromResources(ResourceName: string);
begin
  {$IFDEF MSWINDOWS}
  Icon := LoadIcon(hInstance, PChar(ResourceName));
  {$ENDIF}
end;

destructor TTrayIcon.Destroy;
begin
  if FShowing then
    Hide;
  TrayList.Delete(Self);
  inherited;
end;

procedure TTrayIcon.DoOnClick;
begin
  if Assigned(FOnClick) then
    FOnClick(Self);
end;

procedure TTrayIcon.DoOnDblClick;
begin
  if Assigned(FOnDblClick) then
    FOnDblClick(Self);
end;

procedure TTrayIcon.DoOnPopup;
{$IFDEF MSWINDOWS}
var
  CurPos: TPoint;
begin
  SetForegroundWindow(FWindowHandle);
  GetCursorPos(CurPos);
  if Assigned(FPopupMenu) then
    FPopupMenu.Popup(CurPos.X, CurPos.Y - FPopupOffset);
  {$ELSE}
begin
  {$ENDIF}
end;

procedure TTrayIcon.DoOnRightClick;
begin
  if Assigned(FOnPopup) then
    FOnPopup(Self)
  else
    DoOnPopup;
end;

{ TTrayIcon.TTrayList }

procedure TTrayIcon.TTrayList.Delete(TrayIcon: TTrayIcon);
var
  i: Integer;
begin
  for i := 0 to Self.Count - 1 do
    if Self[i] = TrayIcon then
      Self.Delete(i);
end;

function TTrayIcon.TTrayList.GetByID(ID: Integer; var TrayIcon: TTrayIcon): Boolean;
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
  TTrayIcon.TrayList := TTrayIcon.TTrayList.Create;
  TTrayIcon.NeedHook := True;
  TTrayIcon.IDs := 0;

finalization
  TTrayIcon.TrayList.Free;

end.

