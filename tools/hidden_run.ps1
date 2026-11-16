# Runs a command line on a separate, never-shown Windows desktop, so nothing it
# opens can appear on, take focus from, or clip the cursor of the user's desktop.
#   & hidden_run.ps1 -Cmd '<full command line>' -Log <file> [-TimeoutSec N] [-Cwd dir]
param([string]$Cmd, [string]$Log, [int]$TimeoutSec = 300, [string]$Cwd = "")

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class HiddenDesk2 {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct STARTUPINFO {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr CreateDesktopW(string name, IntPtr dev, IntPtr devmode, int flags, uint access, IntPtr sa);
    [DllImport("user32.dll", SetLastError = true)]
    static extern bool CloseDesktop(IntPtr h);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CreateProcessW(string app, System.Text.StringBuilder cmd, IntPtr pa, IntPtr ta, bool inherit,
        uint flags, IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32.dll")] static extern bool GetExitCodeProcess(IntPtr h, out uint code);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);

    // Returns: exit code; -1 timeout (pid in `pid`); -2 / -3 failed (error in `err`).
    public static int Run(string desk, string app, string line, string cwd, int timeoutMs, out int pid, out int err) {
        pid = 0; err = 0;
        IntPtr d = CreateDesktopW(desk, IntPtr.Zero, IntPtr.Zero, 0, 0x10000000, IntPtr.Zero);
        if (d == IntPtr.Zero) { err = Marshal.GetLastWin32Error(); return -2; }
        STARTUPINFO si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
        si.lpDesktop = "winsta0\\" + desk;
        PROCESS_INFORMATION pi;
        bool ok = CreateProcessW(app, new System.Text.StringBuilder(line), IntPtr.Zero, IntPtr.Zero, false, 0x08000000, IntPtr.Zero, cwd, ref si, out pi);
        if (!ok) { err = Marshal.GetLastWin32Error(); CloseDesktop(d); return -3; }
        pid = pi.dwProcessId;
        uint r = WaitForSingleObject(pi.hProcess, (uint)timeoutMs);
        uint code = 0;
        int ret;
        if (r != 0) { ret = -1; } else { GetExitCodeProcess(pi.hProcess, out code); ret = (int)code; }
        CloseHandle(pi.hProcess); CloseHandle(pi.hThread);
        if (ret != -1) CloseDesktop(d);
        return ret;
    }
}
"@

$name = "claude_tests_" + $PID
if ($Cwd -eq "") { $Cwd = (Get-Location).Path }
$line = 'cmd.exe /d /s /c "' + $Cmd + ' > "' + $Log + '" 2>&1"'
$procId = 0; $err = 0
$code = [HiddenDesk2]::Run($name, $env:ComSpec, $line, $Cwd, $TimeoutSec * 1000, [ref]$procId, [ref]$err)
if ($code -eq -1) {
    Write-Output "TIMEOUT: killing the process tree"
    & taskkill /PID $procId /T /F | Out-Null
    $code = 99
} elseif ($code -lt 0) {
    Write-Output ("launch failed, stage " + $code + ", win32 error " + $err)
    $code = 98
}
Write-Output ("exit " + $code)
exit $code
