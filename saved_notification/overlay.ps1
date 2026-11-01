param(
    [string]$Text = "Replay saved!",
    [int]$Duration = 3,
    [int]$Margin = 20,
    [int]$FontSize = 16
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Окно, которое не забирает фокус, не видно в Alt+Tab и пропускает клики мыши
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
using System;
using System.Windows.Forms;
using System.Runtime.InteropServices;

public class ToastForm : Form
{
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();

    public ToastForm() { this.DoubleBuffered = true; }

    protected override bool ShowWithoutActivation { get { return true; } }

    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams cp = base.CreateParams;
            // TOPMOST | TOOLWINDOW | NOACTIVATE | TRANSPARENT (click-through)
            cp.ExStyle |= 0x00000008 | 0x00000080 | 0x08000000 | 0x00000020;
            return cp;
        }
    }
}
"@

[void][ToastForm]::SetProcessDPIAware()

# масштаб Windows (100% = 1.0, 150% = 1.5 ...)
$gtmp = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
$scale = $gtmp.DpiX / 96.0
$gtmp.Dispose()

$maxOpacity = 0.95
$inMs   = 350
$outMs  = 300
$holdMs = [Math]::Max(1, $Duration) * 1000
$slideDist = [int](70 * $scale)
$Margin = [int]($Margin * $scale)

# ---- геометрия: квадрат ----
$side = [int]($FontSize * 7 * $scale)
$pad  = [int]($side * 0.10)
$icon = [int]($side * 0.38)
$gap  = [int]($side * 0.06)
$textW = $side - 2 * $pad
$flags = [System.Windows.Forms.TextFormatFlags]'WordBreak, HorizontalCenter, NoPadding, Top'

# подбираем размер шрифта, чтобы текст поместился под иконкой
$textMaxH = $side - 2 * $pad - $icon - $gap
$fs = [double]($FontSize * 0.8)
do {
    $font = New-Object System.Drawing.Font('Segoe UI', [single]$fs, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Point)
    $ts = [System.Windows.Forms.TextRenderer]::MeasureText($Text, $font, (New-Object System.Drawing.Size($textW, 10000)), $flags)
    if ($ts.Height -le $textMaxH) { break }
    $font.Dispose()
    $fs -= 0.5
} while ($fs -gt 6)

$contentH = $icon + $gap + $ts.Height
$iconX = [int](($side - $icon) / 2)
$iconY = [int](($side - $contentH) / 2)
$textRect = New-Object System.Drawing.Rectangle($pad, ($iconY + $icon + $gap), $textW, $ts.Height)

# ---- окно ----
$form = New-Object ToastForm
$form.FormBorderStyle = 'None'
$form.AllowTransparency = $true
$form.Opacity = 0
$form.BackColor = [System.Drawing.Color]::FromArgb(46, 204, 113)
$form.ShowInTaskbar = $false
$form.StartPosition = 'Manual'
$form.ClientSize = New-Object System.Drawing.Size($side, $side)

# скруглённые углы
$r = [int]($side * 0.22)
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$path.AddArc(0, 0, $r, $r, 180, 90)
$path.AddArc($side - $r, 0, $r, $r, 270, 90)
$path.AddArc($side - $r, $side - $r, $r, $r, 0, 90)
$path.AddArc(0, $side - $r, $r, $r, 90, 90)
$path.CloseFigure()
$form.Region = New-Object System.Drawing.Region($path)

# монитор, на котором курсор
$cursor = [System.Windows.Forms.Cursor]::Position
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
foreach ($s in [System.Windows.Forms.Screen]::AllScreens) {
    if ($s.Bounds.Contains($cursor)) { $wa = $s.WorkingArea; break }
}
$finalX = $wa.Right - $side - $Margin
$y      = $wa.Top + $Margin
$form.Location = New-Object System.Drawing.Point(($finalX + $slideDist), $y)

# ---- отрисовка: круг с галочкой + текст ----
$form.Add_Paint({
    param($sender, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, [single]($side * 0.035))
    $pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'

    $g.DrawEllipse($pen, [single]$iconX, [single]$iconY, [single]$icon, [single]$icon)

    $pts = [System.Drawing.PointF[]]@(
        (New-Object System.Drawing.PointF(($iconX + $icon * 0.28), ($iconY + $icon * 0.52))),
        (New-Object System.Drawing.PointF(($iconX + $icon * 0.44), ($iconY + $icon * 0.68))),
        (New-Object System.Drawing.PointF(($iconX + $icon * 0.72), ($iconY + $icon * 0.34)))
    )
    $g.DrawLines($pen, $pts)
    $pen.Dispose()

    [System.Windows.Forms.TextRenderer]::DrawText($g, $Text, $font, $textRect, [System.Drawing.Color]::White, $flags)
})

# ---- анимация ----
$sw = New-Object System.Diagnostics.Stopwatch
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 10

$timer.Add_Tick({
    $t = $sw.ElapsedMilliseconds
    if ($t -lt $inMs) {
        $p = $t / $inMs
        $e = 1 - [Math]::Pow(1 - $p, 3)
        $form.Left = [int]($finalX + (1 - $e) * $slideDist)
        $form.Opacity = $maxOpacity * $e
    }
    elseif ($t -lt ($inMs + $holdMs)) {
        $form.Left = $finalX
        $form.Opacity = $maxOpacity
    }
    elseif ($t -lt ($inMs + $holdMs + $outMs)) {
        $p = ($t - $inMs - $holdMs) / $outMs
        $e = [Math]::Pow($p, 3)
        $form.Left = [int]($finalX + $e * $slideDist)
        $form.Opacity = $maxOpacity * (1 - $p)
    }
    else {
        $timer.Stop()
        $form.Close()
    }
})

$form.Add_Shown({ $sw.Start(); $timer.Start() })

[System.Windows.Forms.Application]::Run($form)