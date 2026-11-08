function Complete-ChangelogEditor($Editor) {
    try {
        $Editor.Notes = ConvertTo-ModChangelogNotes $Editor.TextBox.Text $Editor.Release
        $Editor.ErrorLabel.Text = ''
        return $true
    } catch {
        $Editor.Notes = $null
        $Editor.ErrorLabel.Text = $_.Exception.Message
        return $false
    }
}

function New-ChangelogEditor([string]$Mod, [string]$Release) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne [Threading.ApartmentState]::STA) { throw 'Run Add Changelog using powershell.exe -STA for the paste window.' }
    $form = [Windows.Forms.Form]::new()
    $form.Text = "Add Changelog - $Mod $Release"
    $form.StartPosition = [Windows.Forms.FormStartPosition]::CenterScreen
    $form.ClientSize = [Drawing.Size]::new(900, 650)
    $form.MinimumSize = [Drawing.Size]::new(650, 450)
    $form.AutoScaleMode = [Windows.Forms.AutoScaleMode]::Font
    $layout = [Windows.Forms.TableLayoutPanel]::new()
    $layout.Dock = [Windows.Forms.DockStyle]::Fill
    $layout.Padding = [Windows.Forms.Padding]::new(12)
    $layout.ColumnCount = 1; $layout.RowCount = 4
    $layout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent, 100)) | Out-Null
    foreach ($style in @(
        [Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize),
        [Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent, 100),
        [Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize),
        [Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize)
    )) { $layout.RowStyles.Add($style) | Out-Null }
    $instructions = [Windows.Forms.Label]::new()
    $instructions.AutoSize = $true
    $instructions.Margin = [Windows.Forms.Padding]::new(0, 0, 0, 10)
    $instructions.Text = "Paste your full Markdown changelog with Ctrl+V, then click Save (or Ctrl+Enter).`r`nKeep ## Added, ## Changed, ## Fixed, bullets and blank lines. The ## $Release heading is added automatically."
    $textBox = [Windows.Forms.TextBox]::new()
    $textBox.Multiline = $true
    $textBox.AcceptsReturn = $true; $textBox.AcceptsTab = $true
    $textBox.ScrollBars = [Windows.Forms.ScrollBars]::Both
    $textBox.WordWrap = $false; $textBox.MaxLength = 0
    $textBox.Dock = [Windows.Forms.DockStyle]::Fill
    $textBox.Font = [Drawing.Font]::new('Consolas', 10)
    $textBox.TabIndex = 0
    $errorLabel = [Windows.Forms.Label]::new()
    $errorLabel.AutoSize = $true
    $errorLabel.ForeColor = [Drawing.Color]::Firebrick
    $errorLabel.Margin = [Windows.Forms.Padding]::new(0, 8, 0, 8)
    $buttons = [Windows.Forms.FlowLayoutPanel]::new()
    $buttons.AutoSize = $true
    $buttons.Dock = [Windows.Forms.DockStyle]::Fill
    $buttons.FlowDirection = [Windows.Forms.FlowDirection]::RightToLeft
    $cancel = [Windows.Forms.Button]::new()
    $cancel.Text = 'Cancel'; $cancel.AutoSize = $true
    $cancel.DialogResult = [Windows.Forms.DialogResult]::Cancel
    $save = [Windows.Forms.Button]::new()
    $save.Text = 'Save'; $save.AutoSize = $true
    $buttons.Controls.Add($cancel); $buttons.Controls.Add($save)
    $layout.Controls.Add($instructions, 0, 0)
    $layout.Controls.Add($textBox, 0, 1)
    $layout.Controls.Add($errorLabel, 0, 2)
    $layout.Controls.Add($buttons, 0, 3)
    $form.Controls.Add($layout)
    $form.CancelButton = $cancel
    # No AcceptButton: ordinary Enter must insert a newline, never submit notes.
    $editor = [pscustomobject]@{ Form = $form; TextBox = $textBox; SaveButton = $save; CancelButton = $cancel; ErrorLabel = $errorLabel; Release = $Release; Notes = $null }
    $form.Tag = $editor; $textBox.Tag = $editor; $save.Tag = $editor
    $save.Add_Click({
        param($sender, $eventArgs)
        $state = $sender.Tag
        if (Complete-ChangelogEditor $state) {
            $state.Form.DialogResult = [Windows.Forms.DialogResult]::OK
            $state.Form.Close()
        }
    })
    $textBox.Add_KeyDown({
        param($sender, $eventArgs)
        if ($eventArgs.Control -and $eventArgs.KeyCode -eq [Windows.Forms.Keys]::Enter) {
            $eventArgs.SuppressKeyPress = $true
            $sender.Tag.SaveButton.PerformClick()
        }
    })
    $form.Add_Shown({ param($sender, $eventArgs) $sender.Tag.TextBox.Focus() | Out-Null })
    return $editor
}

function Show-ChangelogNotesEditor([string]$Mod, [string]$Release) {
    $previousContext = [Threading.SynchronizationContext]::Current
    $editor = New-ChangelogEditor $Mod $Release
    try {
        if ($editor.Form.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) { return $editor.Notes }
        return $null
    } finally {
        $editor.Form.Dispose()
        [Threading.SynchronizationContext]::SetSynchronizationContext($previousContext)
    }
}
