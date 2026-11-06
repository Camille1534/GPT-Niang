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
  $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  Receive-TaskPetState @{state='coding';at=$now}
  Assert ($script:taskPetState-eq 'coding') 'Fresh state is accepted'
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
  function Test-WidgetUpdateEditor {return $false}
  Tick-TaskPet $now $true
  Assert ($script:openCount-eq 1 -and $script:ui.QuoteText.Text) 'Visible idle bubble displays state speech and native motion'
  $script:taskPetPending=$true
  Tick-TaskPet ($now+1000) $true
  Assert ($script:openCount-eq 1) 'Speech is throttled'
  Tick-TaskPet ($now+16000) $false
  Assert ($script:openCount-eq 1) 'Hidden widget does not display speech'
  Write-Output 'PASS: task speech, edits, backup, stale events, disabled state, native animation and throttling'
}finally{
  if($script:window){$script:window.Close()}
  Remove-Item -LiteralPath $script:dataDir -Recurse -Force
}
