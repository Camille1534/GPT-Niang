$script:taskPetEnabled=$true
$script:taskPetState='idle';$script:taskPetAt=0;$script:taskPetShownAt=0;$script:taskPetPending=$false
$script:taskPetQuotes=@{
 idle=@('我在这里，随时可以开工。','休息一下，下一步交给我陪你。')
 thinking=@('正在认真思考，龙角都转起来啦。','让我理一理思路，很快就好。')
 working=@('工具正在忙碌，我也在陪着你。','一步一步，把任务做好。')
 searching=@('让我找找可靠的资料。','正在翻阅线索，稍等一下。')
 coding=@('开始动手改代码啦。','把想法变成代码，一点点完成。')
 waiting=@('有个问题需要你看看哦。','等你的选择，我就在这里。')
 completed=@('这轮任务完成啦，来看看结果吧！','辛苦啦，回复已经准备好。')
 error=@('遇到问题啦，看看日志再决定下一步。','这一步没成功，我们看看原因。')
 interrupted=@('这轮先停下了，随时可以继续。','收到，先收好小爪子。')
}
$script:taskPetLastQuote=@{}
function Get-TaskPetQuotes([string]$State) {
  $file=Join-Path $script:dataDir ('task-quotes\'+$State+'\quotes.json')
  if([IO.File]::Exists($file)){try{$rows=@(Read-WidgetQuoteFile $file);if($rows.Count){return $rows}}catch{}}
  return @(ConvertTo-WidgetQuoteRows $script:taskPetQuotes[$State])
}
function Get-TaskPetQuote([string]$State) {
  $rows=@(Get-TaskPetQuotes $State);$last=$script:taskPetLastQuote[$State]
  $choices=@($rows|Where-Object{$_.text-ne $last});if(!$choices.Count){$choices=$rows}
  $sum=0.0;foreach($row in $choices){$sum+=$row.weight}
  $pick=$script:widgetQuoteRandom.NextDouble()*$sum;$text=$choices[-1].text
  foreach($row in $choices){$pick-=$row.weight;if($pick-lt 0){$text=$row.text;break}}
  $script:taskPetLastQuote[$State]=$text;return $text
}
function Receive-TaskPetState($Event) {
  if(!$script:taskPetEnabled -or !$script:taskPetQuotes.ContainsKey([string]$Event.state)){return}
  $at=0.0;if(![double]::TryParse([string]$Event.at,[ref]$at)){return}
  $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  if($at-lt $script:taskPetAt -or $now-$at-gt 30000 -or $at-gt $now+5000){return}
  $script:taskPetAt=$at;$script:taskPetState=[string]$Event.state;$script:taskPetPending=$true
}
function Set-TaskPetEnabled([bool]$Enabled) {
  $script:taskPetEnabled=$Enabled;$script:taskPetPending=$false
  if($Enabled){Start-CompletionMonitor}
  elseif(!$script:completionNotificationsEnabled){Stop-CompletionMonitor}
  Save-Settings;Update-WidgetSettingsMenu
}
function Tick-TaskPet([long]$Now,[bool]$Visible) {
  if(!$script:taskPetEnabled){return}
  if($Now-$script:taskPetShownAt-ge 60000){$script:taskPetPending=$true}
  if($script:taskPetState-ne 'idle' -and $Now-$script:taskPetAt-gt 120000){$script:taskPetState='idle';$script:taskPetPending=$true}
  if(!$Visible -or !$script:window.IsVisible -or [bool]$script:drag -or $script:context.IsOpen -or $script:settingsSizePreview -or (Test-WidgetUpdateEditor) -or !$script:collapsed -or $script:completionPending){return}
  if(!$script:taskPetPending -or $Now-$script:taskPetShownAt-lt 15000){return}
  $script:taskPetPending=$false;$script:taskPetShownAt=$Now
  Open-WidgetBubble 'quote'
  $script:ui.QuoteText.Text=Get-TaskPetQuote $script:taskPetState;Fit-QuoteText
  # A short native WPF motion leaves drag, scaling and music transforms intact.
  if(!$script:widgetMusic -or !$script:widgetMusic.Enabled){
    $motion=[Windows.Media.TranslateTransform]::new();$script:ui.Girl.RenderTransform=$motion
    $animation=[Windows.Media.Animation.DoubleAnimation]::new()
    $animation.From=0;$animation.To=if($script:taskPetState-eq 'completed'){-10}else{-3}
    $animation.Duration=[Windows.Duration]::new([TimeSpan]::FromMilliseconds(260));$animation.AutoReverse=$true
    $animation.RepeatBehavior=[Windows.Media.Animation.RepeatBehavior]::new(2)
    $motion.BeginAnimation([Windows.Media.TranslateTransform]::YProperty,$animation)
  }
}
function Get-TaskPetStatus {
  return @{enabled=[bool]$script:taskPetEnabled;state=$script:taskPetState;updatedAt=$script:taskPetAt;shownAt=$script:taskPetShownAt;pending=[bool]$script:taskPetPending}
}
function Open-TaskPetQuoteEditor {
  if($script:taskPetEditor -and $script:taskPetEditor.IsVisible){$null=$script:taskPetEditor.Activate();return}
  $editor=[Windows.Markup.XamlReader]::Parse(@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="GPT 娘 · 任务台词" Width="540" Height="470" WindowStartupLocation="CenterScreen" FontFamily="Microsoft YaHei UI" FontSize="15" Background="#FAF8FD">
 <DockPanel Margin="20">
  <TextBlock DockPanel.Dock="Top" Text="按任务状态编辑台词，一行一句；支持 3 | 台词 权重。" TextWrapping="Wrap" Margin="0,0,0,12"/>
  <ComboBox x:Name="State" DockPanel.Dock="Top" Margin="0,0,0,12"/>
  <StackPanel DockPanel.Dock="Bottom"><TextBlock x:Name="Feedback" TextWrapping="Wrap" Margin="0,10"/><StackPanel Orientation="Horizontal"><Button x:Name="Save" Content="保存此状态" Padding="16,6"/><Button x:Name="Reset" Content="恢复此状态默认台词" Padding="16,6" Margin="10,0,0,0"/></StackPanel></StackPanel>
  <TextBox x:Name="Lines" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap" Padding="10"/>
 </DockPanel>
</Window>
'@)
  $script:taskPetEditor=$editor
  $names=[ordered]@{idle='待机';thinking='思考';working='执行工具';searching='搜索';coding='写代码';waiting='等待你回应';completed='已完成';error='发生错误';interrupted='已中断'}
  foreach($key in $names.Keys){$item=[Windows.Controls.ComboBoxItem]::new();$item.Tag=$key;$item.Content=$names[$key];$null=$editor.FindName('State').Items.Add($item)}
  $editor.FindName('State').Add_SelectionChanged({
    $e=$script:taskPetEditor;$state=[string]$e.FindName('State').SelectedItem.Tag
    $e.FindName('Lines').Text=((Get-TaskPetQuotes $state)|ForEach-Object{([string]$_.weight)+' | '+$_.text})-join "`r`n"
    $e.FindName('Feedback').Text='切换状态前请先保存。文件仅保存在本机。'
  })
  $editor.FindName('Save').Add_Click({try{
    $e=$script:taskPetEditor;$state=[string]$e.FindName('State').SelectedItem.Tag
    $rows=@(foreach($line in ($e.FindName('Lines').Text-split '\r?\n')){
      if(!$line.Trim()){continue}
      if($line-match '^\s*(\d+(?:\.\d+)?)\s*\|\s*(.+)$'){@{text=$Matches[2];weight=[double]::Parse($Matches[1],[Globalization.CultureInfo]::InvariantCulture)}}else{@{text=$line;weight=1}}
    })
    $null=Save-WidgetQuotes (Join-Path $script:dataDir ('task-quotes\'+$state)) $rows
    $e.FindName('Feedback').Text='已保存，下次显示此状态时生效。'
  }catch{$script:taskPetEditor.FindName('Feedback').Text=$_.Exception.Message}})
  $editor.FindName('Reset').Add_Click({
    $e=$script:taskPetEditor;$state=[string]$e.FindName('State').SelectedItem.Tag
    try{$null=Reset-WidgetQuotes (Join-Path $script:dataDir ('task-quotes\'+$state));$e.FindName('Lines').Text=$script:taskPetQuotes[$state]-join "`r`n";$e.FindName('Feedback').Text='已恢复；旧台词已备份。'}catch{$e.FindName('Feedback').Text=$_.Exception.Message}
  })
  $editor.FindName('State').SelectedIndex=0;$null=$editor.ShowDialog()
}
