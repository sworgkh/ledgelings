using System.Runtime.InteropServices;

namespace Ledgelings.Native;

/// <summary>Where a secret lives: the API key goes here, never in the settings file.</summary>
public interface ISecretStore
{
    string? Get(string account);
    /// <summary>Null or empty removes the item.</summary>
    void Set(string account, string? value);
}

/// <summary>Secrets in the Windows Credential Manager, as generic credentials named
/// <c>Ledgelings/&lt;account&gt;</c>, so they are easy to find in Control Panel.</summary>
public sealed class CredentialStore : ISecretStore
{
    private const uint CRED_TYPE_GENERIC = 1;
    private const uint CRED_PERSIST_LOCAL_MACHINE = 2;

    public string Service { get; }

    public CredentialStore(string service = "Ledgelings") { Service = service; }

    private string Target(string account) => $"{Service}/{account}";

    public string? Get(string account)
    {
        if (!CredReadW(Target(account), CRED_TYPE_GENERIC, 0, out var handle)) return null;
        try
        {
            var cred = Marshal.PtrToStructure<CREDENTIALW>(handle);
            if (cred.CredentialBlob == IntPtr.Zero || cred.CredentialBlobSize == 0) return "";
            var bytes = new byte[cred.CredentialBlobSize];
            Marshal.Copy(cred.CredentialBlob, bytes, 0, bytes.Length);
            return System.Text.Encoding.UTF8.GetString(bytes);
        }
        finally { CredFree(handle); }
    }

    public void Set(string account, string? value)
    {
        if (string.IsNullOrEmpty(value)) { CredDeleteW(Target(account), CRED_TYPE_GENERIC, 0); return; }
        var bytes = System.Text.Encoding.UTF8.GetBytes(value);
        var blob = Marshal.AllocHGlobal(bytes.Length);
        try
        {
            Marshal.Copy(bytes, 0, blob, bytes.Length);
            var cred = new CREDENTIALW
            {
                Type = CRED_TYPE_GENERIC,
                TargetName = Target(account),
                CredentialBlobSize = (uint)bytes.Length,
                CredentialBlob = blob,
                Persist = CRED_PERSIST_LOCAL_MACHINE,
                UserName = account,
            };
            CredWriteW(ref cred, 0);
        }
        finally { Marshal.FreeHGlobal(blob); }
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct CREDENTIALW
    {
        public uint Flags;
        public uint Type;
        public string TargetName;
        public string? Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        public string? TargetAlias;
        public string? UserName;
    }

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredReadW(string target, uint type, uint flags, out IntPtr credential);

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredWriteW(ref CREDENTIALW credential, uint flags);

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredDeleteW(string target, uint type, uint flags);

    [DllImport("advapi32.dll")]
    private static extern void CredFree(IntPtr buffer);
}

/// <summary>For tests: secrets that live only as long as the object.</summary>
public sealed class MemorySecretStore : ISecretStore
{
    private readonly Dictionary<string, string> items = new();
    public string? Get(string account) => items.TryGetValue(account, out var v) ? v : null;
    public void Set(string account, string? value)
    {
        if (string.IsNullOrEmpty(value)) items.Remove(account); else items[account] = value;
    }
}
