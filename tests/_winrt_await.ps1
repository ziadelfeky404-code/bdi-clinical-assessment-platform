$winrtAsm = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'System.Runtime.WindowsRuntime' } | Select-Object -First 1
if ($null -eq $winrtAsm) { $winrtAsm = [System.Reflection.Assembly]::Load('System.Runtime.WindowsRuntime') }
$winmd = 'C:\Windows\System32\WinMetadata\Windows.Foundation.winmd'

$src = @'
using System;
using System.Threading.Tasks;
using Windows.Foundation;
public static class WinRTAwait
{
    public static T Await<T>(IAsyncOperation<T> op)
    {
        var tcs = new TaskCompletionSource<T>();
        op.Completed = (info, status) =>
        {
            if (status == AsyncStatus.Completed) tcs.TrySetResult(op.GetResults());
            else if (status == AsyncStatus.Error) tcs.TrySetException(info.ErrorCode);
            else tcs.TrySetCanceled();
        };
        return tcs.Task.GetAwaiter().GetResult();
    }
}
'@
$provider = New-Object Microsoft.CSharp.CSharpCodeProvider
$params = New-Object System.CodeDom.Compiler.CompilerParameters
$params.GenerateInMemory = $true
$refs = @(
  'C:\Program Files (x86)\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8\Facades\System.Runtime.dll',
  'C:\Program Files (x86)\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8\Facades\System.Threading.Tasks.dll',
  'C:\Program Files (x86)\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8\mscorlib.dll',
  'C:\Program Files (x86)\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8\System.dll',
  'C:\Program Files (x86)\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8\System.Core.dll'
)
foreach ($ref in $refs) { if (Test-Path $ref) { $params.ReferencedAssemblies.Add($ref) | Out-Null } }
$params.ReferencedAssemblies.Add($winrtAsm.Location) | Out-Null
$params.ReferencedAssemblies.Add($winmd) | Out-Null
$result = $provider.CompileAssemblyFromSource($params, $src)
if ($result.Errors.Count -gt 0) { $result.Errors | ForEach-Object { Write-Error $_.ErrorText }; throw 'compile failed' }
