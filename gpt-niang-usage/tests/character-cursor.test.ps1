param([string]$TestRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$script:appDir=Split-Path $TestRoot -Parent
. (Join-Path $script:appDir 'runtime\character-cursor.ps1')
$source=[IO.File]::ReadAllText((Join-Path $script:appDir 'widget.ps1'),[Text.Encoding]::UTF8)
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
foreach($name in @('Write-WidgetJson','Save-Settings')){
  $definition=$ast.Find({param($n)$n-is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name-eq $name},$true)
  . ([ScriptBlock]::Create($definition.Extent.Text))
}
$testDir=Join-Path ([IO.Path]::GetTempPath()) ('gpt-cursor-'+[Guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($testDir)
$settingsFile=Join-Path $testDir 'settings.json'
$script:window=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $script:appDir 'widget.xaml'),[Text.Encoding]::UTF8))
$script:ui=@{}
foreach($name in @('Girl','Bubble','MenuButton')){$script:ui[$name]=$script:window.FindName($name)}
function Assert($condition,[string]$message){if(!$condition){throw $message}}
$originalApp=$script:appDir
$originalOverride=[Windows.Input.Mouse]::OverrideCursor
try{
  Initialize-WidgetCharacterCursor $null
  Assert (!$script:headPatCursorEnabled -and !$script:headPatCursor) 'Legacy preferences must preserve the system hand without loading a custom cursor'
  foreach($invalid in @('true',1,$null)){
    Initialize-WidgetCharacterCursor @{headPatCursor=$invalid}
    Assert (!$script:headPatCursorEnabled) 'Only a Boolean opt-in is accepted'
  }
  $script:scale=0.7;$script:bubbleScale=0.8;$script:autoQuoteEnabled=$true;$script:autoQuoteIntervalSeconds=60
  Set-WidgetHeadPatCursor $true
  Assert ($script:headPatCursor -and !$script:headPatCursorError -and $script:ui.Girl.Cursor-eq $script:headPatCursor) 'WPF must load and apply the bundled cursor'
  Assert ($script:ui.Bubble.Cursor-eq [Windows.Input.Cursors]::Hand) 'Bubble cursor must remain unchanged'
  Assert ([Windows.Input.Mouse]::OverrideCursor-eq $originalOverride) 'Character hover must not override the cursor globally'
  $saved=Get-Content -LiteralPath $settingsFile -Raw|ConvertFrom-Json
  Assert ($saved.headPatCursor -eq $true -and $saved.autoQuoteEnabled -and $saved.autoQuoteIntervalSeconds-eq 60 -and $saved.scale-eq 0.7 -and $saved.bubbleScale-eq 0.8) 'Actual Save-Settings must retain cursor, quote and sizing preferences'
  $down=[Windows.Input.MouseButtonEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice,0,[Windows.Input.MouseButton]::Left)
  $down.RoutedEvent=[Windows.UIElement]::PreviewMouseLeftButtonDownEvent
  $script:ui.Girl.RaiseEvent($down)
  Assert ($script:ui.Girl.Cursor-eq $script:headPatPressedCursor -and $script:headPatPressedCursor-ne $script:headPatCursor) 'Press selects distinct cursor'
  $up=[Windows.Input.MouseButtonEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice,0,[Windows.Input.MouseButton]::Left)
  $up.RoutedEvent=[Windows.UIElement]::PreviewMouseLeftButtonUpEvent
  $script:ui.Girl.RaiseEvent($up)
  Assert ($script:ui.Girl.Cursor-eq $script:headPatCursor) 'Release restores hover'
  Set-WidgetHeadPatPressed $true
  $lost=[Windows.Input.MouseEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice,0)
  $lost.RoutedEvent=[Windows.UIElement]::LostMouseCaptureEvent
  $script:ui.Girl.RaiseEvent($lost)
  Assert (!$script:headPatPressed -and $script:ui.Girl.Cursor-eq $script:headPatCursor) 'Lost capture resets press'
  $cached=$script:headPatCursor
  Set-WidgetHeadPatCursor $false
  Assert ($script:ui.Girl.Cursor-eq [Windows.Input.Cursors]::Hand) 'Disabling restores the system hand immediately'
  Assert (!(Get-Content -LiteralPath $settingsFile -Raw|ConvertFrom-Json).headPatCursor) 'Disabling must persist'
  Initialize-WidgetCharacterCursor $saved
  Assert ($script:headPatCursorEnabled -and $script:ui.Girl.Cursor-eq $cached) 'Reload restores the preference and reuses the cached native cursor'
  Close-WidgetCharacterCursor
  $script:appDir=$testDir
  Initialize-WidgetCharacterCursor $saved
  Assert ($script:headPatCursorError -and $script:ui.Girl.Cursor-eq [Windows.Input.Cursors]::Hand) 'Missing asset must fall back without breaking the widget'
  $null=[IO.Directory]::CreateDirectory((Join-Path $testDir 'assets'))
  [IO.File]::WriteAllText((Join-Path $testDir 'assets\head-pat-cursor.cur'),'invalid')
  Update-WidgetCharacterCursor
  Assert ($script:headPatCursorError -and !$script:headPatCursor) 'Invalid cursor must fail safely'
  $script:appDir=$originalApp
  Update-WidgetCharacterCursor
  Assert ($script:headPatCursor -and !$script:headPatCursorError) 'A repaired asset must load on retry'
  $file=Join-Path $script:appDir 'assets\head-pat-cursor.cur'
  $bytes=[IO.File]::ReadAllBytes($file)
  Assert ([BitConverter]::ToUInt16($bytes,2)-eq 2 -and [BitConverter]::ToUInt16($bytes,4)-eq 4) 'Asset must be a multi-resolution Windows cursor'
  $i=0
  foreach($size in @(32,48,64,96)){
    $offset=6+16*$i
    Assert ($bytes[$offset]-eq $size -and $bytes[$offset+1]-eq $size) 'Cursor must include each DPI size'
    Assert ([BitConverter]::ToUInt16($bytes,$offset+4)-eq [Math]::Round(6*$size/32) -and [BitConverter]::ToUInt16($bytes,$offset+6)-eq [Math]::Round(21*$size/32)) 'Every size must keep the hotspot on the touching fingertip'
    $i++
  }
  'PASS: native WPF cursor load, local scope, menu-independent settings, saved opt-in, DPI hotspots, cache and safe fallback'
}finally{
  Close-WidgetCharacterCursor
  $script:window.Close()
  $resolved=[IO.Path]::GetFullPath($testDir)
  $prefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\gpt-cursor-'
  if(!$resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cursor test cleanup target'}
  Remove-Item -LiteralPath $resolved -Recurse -Force
}
