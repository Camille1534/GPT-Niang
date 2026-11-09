param([string]$PreviewDirectory)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$appDir=Split-Path $PSScriptRoot -Parent
. (Join-Path $appDir 'runtime\quotes.ps1')
. (Join-Path $appDir 'runtime\task-pet.ps1')
$script:dataDir=Join-Path ([IO.Path]::GetTempPath()) ('task-pet-'+[Guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $script:dataDir
function Assert($ok,$message){if(!$ok){throw $message}}
try{
  foreach($state in $script:taskPetQuotes.Keys){
    $first=Get-TaskPetQuote $state;$second=Get-TaskPetQuote $state
    Assert ($first -and $second -and $first-ne $second) 'Each state has nonrepeating built-in speech'
  }
  $custom=Join-Path $script:dataDir 'task-quotes\coding'
  $null=Save-WidgetQuotes $custom @(@{text='custom coding';weight=3})
  Assert ((Get-TaskPetQuote 'coding')-eq 'custom coding') 'Custom state speech is selected'
  $null=Save-WidgetQuotes $custom @(@{text='edited coding';weight=1})
  Assert ((Get-TaskPetQuote 'coding')-eq 'edited coding') 'Saved edits are read without restart'
  $null=Reset-WidgetQuotes $custom
  Assert ([IO.File]::Exists((Join-Path $custom 'quotes.json.bak'))) 'Reset preserves a backup'
  Assert ((Get-TaskPetQuote 'coding')-ne 'edited coding') 'Reset restores defaults'
  Save-TaskPetQuoteLines 'coding' "3 | valid`nsecond line"
  $before=[IO.File]::ReadAllText((Join-Path $custom 'quotes.json'))
  $rejected=$false
  try{Save-TaskPetQuoteLines 'coding' ("valid`n"+('x'*201))}catch{$rejected=$true}
  Assert $rejected 'An invalid line cannot silently disappear from a mixed list'
  Assert ([IO.File]::ReadAllText((Join-Path $custom 'quotes.json'))-ceq $before) 'Rejected edits preserve the previous file'
  $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  Receive-TaskPetState @{state='coding';at=$now}
  Assert ($script:taskPetState-eq 'coding') 'Fresh state is accepted'
  $script:taskPetPending=$false
  Receive-TaskPetState @{state='coding';at=$now+1}
  Assert (!$script:taskPetPending -and $script:taskPetAt-eq $now+1) 'Repeated state refreshes freshness without forcing another quote'
  foreach($invalid in @('NaN','Infinity','-Infinity')){Receive-TaskPetState @{state='error';at=$invalid}}
  Assert ($script:taskPetState-eq 'coding') 'Nonfinite timestamps cannot corrupt live state'
  Receive-TaskPetState @{state='completed';at=$now-60000}
  Assert ($script:taskPetState-eq 'coding') 'Old events cannot replace fresh state'
  $script:taskPetEnabled=$false
  Receive-TaskPetState @{state='completed';at=$now+1}
  Assert ($script:taskPetState-eq 'coding') 'Disabled reactions ignore events'
  $script:taskPetEnabled=$true;$script:collapsed=$true;$script:completionPending=$false
  $script:window=New-Object Windows.Window;$script:window.Show()
  $script:context=@{IsOpen=$false};$script:ui=@{Girl=(New-Object Windows.Controls.Image);QuoteText=(New-Object Windows.Controls.TextBlock)}
  $script:openCount=0
  function Open-WidgetBubble($mode){$script:openCount++}
  function Fit-QuoteText {}
  $script:appliedScene=0
  function Apply-Scene {$script:appliedScene++}
  function Test-WidgetUpdateEditor {return $false}
  $script:taskPetPending=$true;Tick-TaskPet $now $true
  Assert ($script:openCount-eq 1 -and $script:ui.QuoteText.Text) 'Visible idle bubble displays state speech and native motion'
  Assert ($script:appliedScene-eq 1) 'Task text reapplies its own scene layout and tooltip'
  $script:taskPetPending=$true
  Tick-TaskPet ($now+1000) $true
  Assert ($script:openCount-eq 1) 'Speech is throttled'
  Tick-TaskPet ($now+16000) $false
  Assert ($script:openCount-eq 1) 'Hidden widget does not display speech'
  $script:taskPetState='completed';$script:taskPetAt=$now;$script:taskPetPending=$false
  Tick-TaskPet ($now+61000) $true
  Assert ($script:openCount-eq 1) 'Completed dialogue is not repeated every minute'
  $script:editorTestError=$null
  $editorTestTimer=[Windows.Threading.DispatcherTimer]::new();$editorTestTimer.Interval=[TimeSpan]::FromMilliseconds(100)
  $editorTestTimer.Add_Tick({param($timer,$event)
    $timer.Stop();$e=$script:taskPetEditor
    try{
      $e.FindName('State').SelectedIndex=4
      $e.FindName('Lines').Text='3 | editor draft'
      $e.FindName('State').SelectedIndex=1
      $e.FindName('State').SelectedIndex=4
      Assert ($e.FindName('Lines').Text-ceq '3 | editor draft') 'Switching states preserves unsaved drafts'
      $e.FindName('Save').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
      Assert ((Get-TaskPetQuote 'coding')-ceq 'editor draft') 'The real editor saves the selected state'
      $e.FindName('Lines').Text='valid'+"`n"+('x'*201)
      $e.FindName('Save').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
      Assert ((Get-TaskPetQuote 'coding')-ceq 'editor draft') 'Invalid editor input preserves saved dialogue'
      Assert ($e.FindName('Feedback').Text-match '2') 'The editor identifies the invalid line'
      $e.FindName('Lines').Text='3 | editor draft'
      $e.FindName('Save').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
      if($PreviewDirectory){
        $null=[IO.Directory]::CreateDirectory($PreviewDirectory)
        $e.UpdateLayout();$bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$e.ActualWidth,[int]$e.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
        $bitmap.Render($e);$encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $stream=[IO.File]::Create((Join-Path $PreviewDirectory 'task-dialogue-editor.png'));try{$encoder.Save($stream)}finally{$stream.Dispose()}
      }
    }catch{
      $script:editorTestError=$_
      $script:taskPetDrafts.Clear();$script:taskPetSavedLines[$script:taskPetEditorState]=$e.FindName('Lines').Text
    }finally{$e.Close()}
  })
  $editorTestTimer.Start();Open-TaskPetQuoteEditor
  if($script:editorTestError){throw $script:editorTestError}
  Write-Output 'PASS: task speech, edits, backup, stale events, disabled state, native animation and throttling'
}finally{
  if($editorTestTimer){$editorTestTimer.Stop()}
  if($script:window){$script:window.Close()}
  Remove-Item -LiteralPath $script:dataDir -Recurse -Force
}
