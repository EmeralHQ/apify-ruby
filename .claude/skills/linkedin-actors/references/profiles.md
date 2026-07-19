# Perfiles de personas

## Actores

| Actor ID | Usuarios | Éxito 30d | Rating | Precio |
|---|---|---|---|---|
| `harvestapi~linkedin-profile-scraper` | 51.351 | **99.8%** (4,1M runs) | 4.77 (53) | PPE `profile`=$0.004, `profile_with_email`=$0.010 |
| `dev_fusion~Linkedin-Profile-Scraper` | 61.894 | **100%** (1,4M runs) | 3.61 (159) | PPE $0.010/item |
| `apimaestro~linkedin-profile-detail` | 16.637 | 100% (222k) | 4.64 (64) | PPE $0.005/item |
| `apimaestro~linkedin-profile-batch-scraper-no-cookies-required` | 11.056 | 100% | 4.38 (20) | PPE $0.005/item |
| `apimaestro~linkedin-profile-full-sections-scraper` | 3.039 | 100% | 5.0 (8) | PPE $0.010/item |
| ~~`curious_coder~linkedin-profile-scraper`~~ | 5.791 | **0.3%** ❌ | 2.70 (13) | — |

> ❌ **No usar `curious_coder~linkedin-profile-scraper`.** 9.338 fallos contra 32 éxitos en 30 días. Único que requiere cookies de LinkedIn.

> ⚠️ **Trampa del plan Free de `dev_fusion`**: máx. 10 perfiles por run, 10 runs/día, **solo UI — sin API ni CLI**, y búsqueda de móvil deshabilitada. Un gem no puede manejarlo en cuenta gratuita.

## Schemas de input (verbatim)

```
harvestapi~linkedin-profile-scraper          (sin campos requeridos)
  profileScraperMode : "Profile details no email ($4 per 1k)"
                     | "Profile details + email search ($10 per 1k)"
  queries            : array   # URLs o public identifiers (campo general)
  urls               : array
  publicIdentifiers  : array
  profileIds         : array
  # pasar al menos uno de urls / publicIdentifiers / profileIds

dev_fusion~Linkedin-Profile-Scraper          requerido: [profileUrls]
  profileUrls        : array   # solo URLs completas https://www.linkedin.com/in/...

apimaestro~linkedin-profile-detail           requerido: [username]
  username           : string  # slug, URL completa, O urn (ACoAAA...)
  includeEmail       : boolean (default false)

apimaestro~linkedin-profile-batch-scraper-no-cookies-required   requerido: [usernames]
  usernames          : array
  includeEmail       : boolean (default false)
```

**Divergencia de diseño que el gem debe absorber:** `harvestapi` usa cuatro arrays opcionales en paralelo, `apimaestro` usa un campo requerido singular/plural, `dev_fusion` usa un array requerido. Una fachada Ruby unificada tipo `profiles(urls:)` aporta valor real acá.

> ⚠️ `profileScraperMode` es **prefill sin default** — si el gem lo omite vía API, el modo queda indefinido, no en el barato. Aplicarlo siempre explícitamente.

## Output — `harvestapi~linkedin-profile-scraper`

Claves verbatim del sample del README:

```
id                  # urn ACoAA...
publicIdentifier, linkedinUrl, firstName, lastName, headline, about
openToWork, hiring, photo, premium, influencer, verified, registeredAt
topSkills, connectionsCount, followerCount

location { linkedinText, countryCode,
           parsed { text, countryCode, regionCode, country, countryFull, state, city } }

currentPosition[]
experience[]      { position, location, employmentType, workplaceType, companyName,
                    companyLinkedinUrl, companyId, companyUniversalName, duration,
                    description, skills[], startDate{month,year,text}, endDate{text} }
education[]       { schoolName, schoolLinkedinUrl, degree, fieldOfStudy, skills[],
                    startDate{}, endDate{}, period }
certifications[]  { title, issuedAt, issuedBy, issuedByLink }
skills[]          { name, positions[] }
languages[]       { name, proficiency }
projects[], volunteering[], receivedRecommendations[], courses[],
publications[], patents[], honorsAndAwards[], featured, moreProfiles[]

# metadata de request — por item:
query{}, status, entityId, requestId
```

> **`status` es por item.** Una fila puede ser un **registro de fallo** con status distinto de 200. El gem debe exponerla como fallo, no parsearla como perfil.

## Output — `dev_fusion~Linkedin-Profile-Scraper`

Forma más plana y distinta. Es el único que trae **email y móvil de forma automática**:

```
linkedinUrl, linkedinPublicUrl, firstName, lastName, fullName, headline
connections, followers, email, mobileNumber, publicIdentifier, urn
jobTitle, jobStartedOn, jobLocation, jobStillWorking,
currentJobDuration, currentJobDurationInYrs
companyName, companyIndustry, companyWebsite, companyLinkedin, companySize
experiences[], educations[], skills[], languages[],
certifications[], publications[], recommendations[]
```

## Sin verificar

- **El nombre del campo de email en el output de `harvestapi` y `apimaestro`.** No aparece en el README, la página del store ni los READMEs de GitHub de HarvestAPI. Tratar el email como passthrough opcional sin tipar hasta confirmarlo contra un run real.
- Output completo de `apimaestro~linkedin-profile-detail` (el README no trae bloque JSON).

## Nota de reutilización

`harvestapi~linkedin-company-employees` devuelve **el mismo schema de perfil** que este actor. Un solo modelo Ruby cubre ambos — y también los perfiles anidados en `harvestapi~linkedin-profile-search`, `~linkedin-post-comments` y `~linkedin-post-reactions`.
