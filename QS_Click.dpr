program QS_Click;

uses
  System.StartUpCopy,
  FMX.Forms,
  u_qs_instance in 'u_qs_instance.pas',
  u_qs_settings in 'u_qs_settings.pas',
  u_main_qs in 'u_main_qs.pas' {Form1},
  u_qs_capture in 'u_qs_capture.pas',
  u_qs_select in 'u_qs_select.pas',
  u_qs_editor in 'u_qs_editor.pas',
  u_qs_tray in 'u_qs_tray.pas';

{$R *.res}

begin
  { Вторая копия не запускает приложение: она просит первую показать окно. }
  if not QSAcquireSingleInstance then
  begin
    QSActivateExistingInstance;
    Exit;
  end;

  try
    Application.Initialize;
    Application.CreateForm(TForm1, Form1);
    Application.Run;
  finally
    QSReleaseSingleInstance;
  end;
end.
