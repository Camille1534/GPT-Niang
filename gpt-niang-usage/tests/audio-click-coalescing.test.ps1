param([string]$TestRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationCore,WindowsBase,System
$app=Split-Path $TestRoot -Parent
. (Join-Path $app 'runtime\audio.ps1')
$script:soundOn=$true;$script:soundVolume=0.9
Initialize-WidgetAudio $app
$a=$script:gptNiangAudio
function Assert($ok,$message){if(!$ok){throw $message}}
try{
  $a.Queue.Dispose();$a.Queue.Wait(2000)
  $probe=[pscustomobject]@{Clips=[Collections.Generic.List[object]]::new();Stops=0}
  $probe|Add-Member ScriptMethod Play {param($clip)$this.Clips.Add($clip)}
  $probe|Add-Member ScriptMethod Stop {$this.Stops++}
  $a.Queue=$probe
  $clock=[pscustomobject]@{IsRunning=$false;Elapsed=[pscustomobject]@{TotalSeconds=0.0}}
  $clock|Add-Member ScriptMethod Restart {$this.IsRunning=$true;$this.Elapsed.TotalSeconds=0.0}
  $clock|Add-Member ScriptMethod Reset {$this.IsRunning=$false;$this.Elapsed.TotalSeconds=0.0}
  $a.PlaybackClock=$clock
  Play-WidgetPressSound;Play-WidgetReleaseSound
  for($i=0;$i-lt 100;$i++){Play-WidgetPressSound;Play-WidgetReleaseSound}
  Assert ($probe.Clips.Count-eq 1 -and $a.PendingRelease) 'Rapid clicks must preserve the first press and pending release'
  Invoke-WidgetReleaseNow
  for($i=0;$i-lt 100;$i++){Play-WidgetPressSound;Play-WidgetReleaseSound}
  Assert ($probe.Clips.Count-eq 2 -and !$a.PendingRelease) 'Release playback must not be interrupted or accumulate clicks'
  $clock.Elapsed.TotalSeconds=$a.PlaybackSeconds+0.01
  Play-WidgetPressSound
  Assert ($probe.Clips.Count-eq 3 -and $a.Pressing) 'A new click after completion must play immediately'
  Stop-WidgetAudio;Play-WidgetPressSound
  Assert ($probe.Clips.Count-eq 4) 'Explicit cancellation must reset the playback guard'
  $script:soundOn=$false;Play-WidgetReleaseSound
  Assert (!$a.PendingRelease -and !$clock.IsRunning) 'Muting must cancel a pending pair'
  'PASS: 200 rapid clicks coalesced, press and release preserved, no backlog, next click and cancellation recover'
}finally{$a.Queue=$null;Close-WidgetAudio}
