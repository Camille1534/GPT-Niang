$script:headPatCursorEnabled=$false
$script:headPatCursor=$null
$script:headPatPressedCursor=$null
$script:headPatPressed=$false
$script:headPatCursorError=$null

function Update-WidgetCharacterCursor {
  if(!$script:ui.Girl){return}
  $script:ui.Girl.Cursor=[Windows.Input.Cursors]::Hand
  $script:headPatCursorError=$null
  if(!$script:headPatCursorEnabled){return}
  if(!$script:headPatCursor){
    $stream=$null
    try{
      $stream=[IO.File]::OpenRead((Join-Path $script:appDir 'assets\head-pat-cursor.cur'))
      $script:headPatCursor=[Windows.Input.Cursor]::new($stream,$true)
      $stream.Dispose();$stream=$null
      $stream=[IO.File]::OpenRead((Join-Path $script:appDir 'assets\head-pat-pressed.cur'))
      $script:headPatPressedCursor=[Windows.Input.Cursor]::new($stream,$true)
    }catch{
      $script:headPatCursorError=$_.Exception.Message
      foreach($cursor in @($script:headPatCursor,$script:headPatPressedCursor)){if($cursor){$cursor.Dispose()}}
      $script:headPatCursor=$null;$script:headPatPressedCursor=$null
    }
    finally{if($stream){$stream.Dispose()}}
  }
  if($script:headPatCursor){$script:ui.Girl.Cursor=if($script:headPatPressed){$script:headPatPressedCursor}else{$script:headPatCursor}}
}
function Set-WidgetHeadPatPressed([bool]$Pressed){
  $script:headPatPressed=$Pressed
  Update-WidgetCharacterCursor
}
function Initialize-WidgetCharacterCursor($Settings) {
  $script:headPatCursorEnabled=($Settings.headPatCursor-is [bool] -and $Settings.headPatCursor)
  Update-WidgetCharacterCursor
  if($script:ui.Girl -and ![object]::ReferenceEquals($script:headPatEventsGirl,$script:ui.Girl)){
    $script:headPatEventsGirl=$script:ui.Girl
    $script:ui.Girl.Add_PreviewMouseLeftButtonDown({Set-WidgetHeadPatPressed $true})
    $script:ui.Girl.Add_PreviewMouseLeftButtonUp({Set-WidgetHeadPatPressed $false})
    $script:ui.Girl.Add_LostMouseCapture({Set-WidgetHeadPatPressed $false})
    $script:ui.Girl.Add_MouseLeave({if(!$script:ui.Girl.IsMouseCaptured){Set-WidgetHeadPatPressed $false}})
  }
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
