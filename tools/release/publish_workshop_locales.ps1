param(
    [Parameter(Mandatory=$true)][string]$GameDirectory,
    [Parameter(Mandatory=$true)][UInt64]$WorkshopId,
    [string]$Manifest,
    [switch]$Publish
)
$ErrorActionPreference = 'Stop'
if (-not $Manifest) { $Manifest = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'workshop-locales.json' }
if ([IntPtr]::Size -ne 4) {
    throw 'Use 32-bit Windows PowerShell to load Noita''s 32-bit steam_api.dll.'
}
$gamePath = (Resolve-Path -LiteralPath $GameDirectory).Path
$manifestPath = (Resolve-Path -LiteralPath $Manifest).Path
$apiPath = Join-Path $gamePath 'steam_api.dll'
if (-not (Test-Path -LiteralPath $apiPath)) { throw 'Noita steam_api.dll was not found.' }
$env:SteamAppId = '881100'
$env:SteamGameId = '881100'
[Environment]::CurrentDirectory = $gamePath
Set-Location -LiteralPath $gamePath

# Flat C exports from the Steamworks API shipped with Noita. No client memory,
# credentials, browser cookies, content files, visibility or tags are modified.
$source = @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class WorkshopLocaleApi {
    const string Dll = "steam_api.dll";
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern IntPtr LoadLibrary(string path);
    [DllImport(Dll, CallingConvention=CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)] public static extern bool SteamAPI_Init();
    [DllImport(Dll, CallingConvention=CallingConvention.Cdecl)] public static extern void SteamAPI_Shutdown();
    [DllImport(Dll, CallingConvention=CallingConvention.Cdecl)] public static extern void SteamAPI_RunCallbacks();
    [DllImport(Dll, CallingConvention=CallingConvention.Cdecl)] public static extern int SteamAPI_GetHSteamUser();
    [DllImport(Dll, CallingConvention=CallingConvention.Cdecl)] public static extern int SteamAPI_GetHSteamPipe();
    [DllImport(Dll, CallingConvention=CallingConvention.Cdecl)] public static extern IntPtr SteamInternal_CreateInterface(string version);
    [DllImport(Dll, CallingConvention=CallingConvention.Cdecl)] public static extern IntPtr SteamAPI_ISteamClient_GetISteamUGC(IntPtr client, int user, int pipe, string version);
    [DllImport(Dll, CallingConvention=CallingConvention.Cdecl)] public static extern IntPtr SteamAPI_ISteamClient_GetISteamUtils(IntPtr client, int pipe, string version);
    [DllImport(Dll, CallingConvention=CallingConvention.Cdecl)] public static extern uint SteamAPI_ISteamUtils_GetAppID(IntPtr utils);
    [DllImport(Dll, CallingConvention=CallingConvention.Cdecl)] public static extern ulong SteamAPI_ISteamUGC_StartItemUpdate(IntPtr ugc, uint app, ulong item);
    [DllImport(Dll, CallingConvention=CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)] public static extern bool SteamAPI_ISteamUGC_SetItemUpdateLanguage(IntPtr ugc, ulong handle, byte[] language);
    [DllImport(Dll, CallingConvention=CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)] public static extern bool SteamAPI_ISteamUGC_SetItemTitle(IntPtr ugc, ulong handle, byte[] title);
    [DllImport(Dll, CallingConvention=CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)] public static extern bool SteamAPI_ISteamUGC_SetItemDescription(IntPtr ugc, ulong handle, byte[] description);
    [DllImport(Dll, CallingConvention=CallingConvention.Cdecl)] public static extern ulong SteamAPI_ISteamUGC_SubmitItemUpdate(IntPtr ugc, ulong handle, IntPtr notes);
    [DllImport(Dll, CallingConvention=CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)] public static extern bool SteamAPI_ISteamUtils_IsAPICallCompleted(IntPtr utils, ulong call, [MarshalAs(UnmanagedType.I1)] out bool failed);
    [DllImport(Dll, CallingConvention=CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)] public static extern bool SteamAPI_ISteamUtils_GetAPICallResult(IntPtr utils, ulong call, out SubmitResult result, int bytes, int callback, [MarshalAs(UnmanagedType.I1)] out bool failed);

    [StructLayout(LayoutKind.Sequential, Pack=8)]
    public struct SubmitResult {
        public int Result;
        [MarshalAs(UnmanagedType.I1)] public bool NeedsAgreement;
        public ulong PublishedFileId;
    }
    public static IntPtr Ugc, Utils;
    static byte[] Utf8(string text) { return Encoding.UTF8.GetBytes(text + "\0"); }
    public static void Initialize(string path) {
        if (LoadLibrary(path) == IntPtr.Zero) throw new Exception("Could not load Noita Steam API");
        if (!SteamAPI_Init()) throw new Exception("Steam API initialization failed; Steam must be running and logged in");
        IntPtr client = SteamInternal_CreateInterface("SteamClient019");
        if (client == IntPtr.Zero) throw new Exception("SteamClient019 unavailable");
        int user = SteamAPI_GetHSteamUser(), pipe = SteamAPI_GetHSteamPipe();
        Ugc = SteamAPI_ISteamClient_GetISteamUGC(client, user, pipe, "STEAMUGC_INTERFACE_VERSION013");
        Utils = SteamAPI_ISteamClient_GetISteamUtils(client, pipe, "SteamUtils009");
        if (Ugc == IntPtr.Zero || Utils == IntPtr.Zero) throw new Exception("Required Noita Steam interfaces unavailable");
        if (SteamAPI_ISteamUtils_GetAppID(Utils) != 881100) throw new Exception("Unexpected Steam app context");
    }
    public static string Update(ulong item, string language, string title, string description) {
        ulong handle = SteamAPI_ISteamUGC_StartItemUpdate(Ugc, 881100, item);
        if (handle == ulong.MaxValue || handle == 0) throw new Exception("Invalid update handle");
        if (!SteamAPI_ISteamUGC_SetItemUpdateLanguage(Ugc, handle, Utf8(language))) throw new Exception("Language rejected");
        if (!SteamAPI_ISteamUGC_SetItemTitle(Ugc, handle, Utf8(title))) throw new Exception("Title rejected");
        if (!SteamAPI_ISteamUGC_SetItemDescription(Ugc, handle, Utf8(description))) throw new Exception("Description rejected");
        ulong call = SteamAPI_ISteamUGC_SubmitItemUpdate(Ugc, handle, IntPtr.Zero);
        if (call == 0) throw new Exception("Invalid submission call");
        DateTime limit = DateTime.UtcNow.AddSeconds(60);
        bool failed;
        while (!SteamAPI_ISteamUtils_IsAPICallCompleted(Utils, call, out failed)) {
            if (DateTime.UtcNow > limit) throw new Exception("Submission outcome unknown after timeout; verify before retrying");
            SteamAPI_RunCallbacks(); Thread.Sleep(100);
        }
        if (failed) throw new Exception("Steam API transport failed; verify before retrying");
        SubmitResult result;
        if (!SteamAPI_ISteamUtils_GetAPICallResult(Utils, call, out result, Marshal.SizeOf(typeof(SubmitResult)), 3404, out failed) || failed)
            throw new Exception("Could not read submission result; verify before retrying");
        if (result.Result != 1) throw new Exception("Steam update failed: EResult=" + result.Result);
        if (result.NeedsAgreement) throw new Exception("Workshop agreement needs user action");
        if (result.PublishedFileId != item) throw new Exception("Unexpected updated item ID");
        return language + ": published title and description for " + result.PublishedFileId;
    }
}
'@
Add-Type -TypeDefinition $source
try {
    [WorkshopLocaleApi]::Initialize($apiPath)
    Write-Output 'Steam interfaces verified: Noita 881100, UGC013, Utils009'
    $locales = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($language in @('english', 'schinese')) {
        $entry = $locales.$language
        if (-not $entry.title -or -not $entry.description) { throw "Missing locale: $language" }
        if ($Publish) {
            Write-Output ([WorkshopLocaleApi]::Update($WorkshopId, $language, $entry.title, $entry.description))
        } else {
            Write-Output ("Prepared {0}: {1}, {2} characters; no update submitted" -f $language, $entry.title, $entry.description.Length)
        }
    }
} finally {
    [WorkshopLocaleApi]::SteamAPI_Shutdown()
}
