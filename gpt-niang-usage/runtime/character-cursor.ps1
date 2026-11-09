$script:headPatCursorEnabled=$false
$script:headPatCursor=$null
$script:headPatPressedCursor=$null
$script:headPatPressed=$false
$script:headPatCursorError=$null
$script:headPatCursorScale=1.0
$script:headPatCursorPixels=0
if(!('GptHeadPatCursorNative' -as [type])){
  Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public sealed class GptHeadPatCursorHandle : SafeHandle {
  public GptHeadPatCursorHandle(IntPtr value):base(IntPtr.Zero,true){SetHandle(value);}
  public override bool IsInvalid {get{return handle==IntPtr.Zero;}}
  protected override bool ReleaseHandle(){return GptHeadPatCursorNative.DestroyCursor(handle);}
}
public static class GptHeadPatCursorNative {
  [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
  static extern IntPtr LoadImage(IntPtr instance,string name,uint type,int width,int height,uint flags);
  [DllImport("user32.dll")]public static extern bool DestroyCursor(IntPtr cursor);
  public static GptHeadPatCursorHandle Load(string path,int size){
    IntPtr handle=LoadImage(IntPtr.Zero,path,2,size,size,0x10);
    if(handle==IntPtr.Zero)throw new Win32Exception(Marshal.GetLastWin32Error());
    return new GptHeadPatCursorHandle(handle);
  }
}
'@
}

function Update-WidgetCharacterCursor {
  if(!$script:ui.Girl){return}
  $script:ui.Girl.Cursor=[Windows.Input.Cursors]::Hand
  $script:headPatCursorError=$null
  if(!$script:headPatCursorEnabled){return}
  $dpi=[Windows.Media.VisualTreeHelper]::GetDpi($script:ui.Girl).DpiScaleX
  $pixels=[int][Math]::Round(32*$script:headPatCursorScale*$dpi)
  if($script:headPatCursor -and $script:headPatCursorPixels-ne $pixels){
    $script:headPatCursor.Dispose();$script:headPatPressedCursor.Dispose()
    $script:headPatCursor=$null;$script:headPatPressedCursor=$null
  }
  if(!$script:headPatCursor){
    try{
      $script:headPatCursor=[Windows.Interop.CursorInteropHelper]::Create([GptHeadPatCursorNative]::Load((Join-Path $script:appDir 'assets\head-pat-cursor.cur'),$pixels))
      $script:headPatPressedCursor=[Windows.Interop.CursorInteropHelper]::Create([GptHeadPatCursorNative]::Load((Join-Path $script:appDir 'assets\head-pat-pressed.cur'),$pixels))
      $script:headPatCursorPixels=$pixels
    }catch{
      $script:headPatCursorError=$_.Exception.Message
      foreach($cursor in @($script:headPatCursor,$script:headPatPressedCursor)){if($cursor){$cursor.Dispose()}}
      $script:headPatCursor=$null;$script:headPatPressedCursor=$null
    }
  }
  if($script:headPatCursor){$script:ui.Girl.Cursor=if($script:headPatPressed){$script:headPatPressedCursor}else{$script:headPatCursor}}
}
function Set-WidgetHeadPatPressed([bool]$Pressed){
  $script:headPatPressed=$Pressed
  Update-WidgetCharacterCursor
}
function Initialize-WidgetCharacterCursor($Settings) {
  $script:headPatCursorEnabled=($Settings.headPatCursor-is [bool] -and $Settings.headPatCursor)
  $script:headPatCursorScale=1.0
  try{$size=[double]$Settings.headPatCursorScale;if($size-ge 0.8 -and $size-le 2){$script:headPatCursorScale=[Math]::Round($size,1)}}catch{}
  Update-WidgetCharacterCursor
  if($script:ui.Girl -and ![object]::ReferenceEquals($script:headPatEventsGirl,$script:ui.Girl)){
    $script:headPatEventsGirl=$script:ui.Girl
    $script:ui.Girl.Add_MouseEnter({Update-WidgetCharacterCursor})
    $script:ui.Girl.Add_PreviewMouseLeftButtonDown({Set-WidgetHeadPatPressed $true})
    $script:ui.Girl.Add_PreviewMouseLeftButtonUp({Set-WidgetHeadPatPressed $false})
    $script:ui.Girl.Add_LostMouseCapture({Set-WidgetHeadPatPressed $false})
    $script:ui.Girl.Add_MouseLeave({if(!$script:ui.Girl.IsMouseCaptured){Set-WidgetHeadPatPressed $false}})
  }
}
function Set-WidgetHeadPatCursorScale([double]$Scale){
  if([double]::IsNaN($Scale) -or [double]::IsInfinity($Scale) -or $Scale-lt 0.8 -or $Scale-gt 2){throw 'Cursor scale must be between 0.8 and 2.'}
  $script:headPatCursorScale=[Math]::Round($Scale,1)
  Update-WidgetCharacterCursor
  Save-Settings
}
function Set-WidgetHeadPatCursor([bool]$Enabled) {
  $script:headPatCursorEnabled=$Enabled
  Update-WidgetCharacterCursor
  Save-Settings
}
function Close-WidgetCharacterCursor {
  if($script:ui.Girl){$script:ui.Girl.Cursor=[Windows.Input.Cursors]::Hand}
  if($script:headPatCursor){$script:headPatCursor.Dispose();$script:headPatCursor=$null}
  if($script:headPatPressedCursor){$script:headPatPressedCursor.Dispose();$script:headPatPressedCursor=$null}
  $script:headPatPressed=$false
}
