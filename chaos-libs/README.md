# chaos-libs

Current release of the Site24x7 Labs Chaos SDK, used by every ZylkerKart service.
All five language SDKs share one version, recorded in `VERSION`.

| Folder | Contents | Consumed by |
|---|---|---|
| `nodejs/` | `site24x7-chaos-sdk-<V>.tgz` (`npm pack` output) | order-service `package.json` (`file:` path) |
| `python/` | `site24x7_chaos-<V>-py3-none-any.whl` | payment-service, ai-assistant `requirements.txt` (`--find-links`) |
| `dotnet/` | `Site24x7.Chaos.<V>.nupkg` (local NuGet feed) | auth-service `nuget.config` |
| `go/` | Go SDK module source (`github.com/site24x7/observe-labs/sdks/go`) | search-service `go.mod` (`replace`) |
| `java/` | Maven repository layout (`com/site24x7/labs/...`) | product-service, storefront `pom.xml` (`file://` repository) |

This folder is written by the observe-labs release workflow. It holds only the
current version, and each release commit bumps every service reference to match.
Don't edit it by hand.

Docker builds receive it as a named build context called `chaos-libs`:

```bash
docker buildx build --build-context chaos-libs=./chaos-libs Applications/ZylkerKart_Ecommerce/services/<service>
```
