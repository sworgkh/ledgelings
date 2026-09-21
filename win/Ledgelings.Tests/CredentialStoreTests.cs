using Ledgelings.Native;

namespace Ledgelings.Tests;

/// <summary>Touches the real Credential Manager, under a throwaway account name that is removed at the end.</summary>
public class CredentialStoreTests
{
    [Fact]
    public void ASecretRoundTripsAndDisappearsWhenCleared()
    {
        var account = "test-" + Guid.NewGuid();
        var store = new CredentialStore("ledgelings-tests");
        try
        {
            Assert.Null(store.Get(account));
            store.Set(account, "sk-or-first");
            Assert.Equal("sk-or-first", store.Get(account));
            store.Set(account, "sk-or-second");
            Assert.Equal("sk-or-second", store.Get(account));
            store.Set(account, "");
            Assert.Null(store.Get(account));
        }
        finally { store.Set(account, null); }
    }
}
