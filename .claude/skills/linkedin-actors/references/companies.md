# Empresas y empleados

## Actores

| Actor ID | Usuarios | Éxito | Precio |
|---|---|---|---|
| `harvestapi~linkedin-company` | 12.325 | 99.9% | arranque $0.00005 + item escalonado **$0.004→$0.003** |
| `apimaestro~linkedin-company-detail` | 4.767 | 100% | $0.005/item |
| `harvestapi~linkedin-company-search` | 4.626 | 100% | `short-company` $0.002→$0.001, `full-company` $0.004→$0.003 |
| `harvestapi~linkedin-company-employees` | 18.571 | 99.6% | `short-profile` $0.003→$0.0015, `full-profile` $0.008→$0.004, `full-profile-with-email` $0.012→$0.008 |
| `apimaestro~linkedin-company-employees-scraper-no-cookies` | 5.060 | 98.8% | $0.010/item |

## Schemas de input

```
harvestapi~linkedin-company
  companies[]   # URLs
  searches[]    # nombres

apimaestro~linkedin-company-detail           requerido: [identifier]
  identifier[]  # slug o URL

harvestapi~linkedin-company-search
  scraperMode   : "short" | "full"
  maxItems      : máx 1000
  searchQuery, locations[], industryIds[], companySize[]
  startPage     : 1..20
  takePages     : 0..20     # 50 empresas por página
  # LinkedIn topea la búsqueda de empresas en la página 20 — cap estructural, no del actor
```

### `harvestapi~linkedin-company-employees` — la superficie más rica de lead-gen

```
profileScraperMode : "Short ($4 per 1k)" | "Full ($8 per 1k)" | "Full + email search ($12 per 1k)"
maxItems, maxItemsPerCompany, companies[], searchQuery

# filtros
locations[], jobTitles[], pastJobTitles[], industryIds[]
yearsAtCurrentCompanyIds[], yearsOfExperienceIds[], seniorityLevelIds[]
functionIds[], companyHeadcount[], recentlyChangedJobs (bool)

# exclusiones (set paralelo completo)
excludeLocations[], excludePastCompanies[], excludeSchools[],
excludeCurrentJobTitles[], excludePastJobTitles[], excludeIndustryIds[],
excludeSeniorityLevelIds[], excludeFunctionIds[]

# paginación y batching
companyBatchMode : "all_at_once" | "one_by_one"
startPage        : 0..100
takePages        : 0..100   # 25 perfiles por página
```

> Devuelve **el mismo schema de perfil** que `harvestapi~linkedin-profile-scraper`. Reutilizar el modelo Ruby de perfil — ver [profiles.md](profiles.md).

## Output — `harvestapi~linkedin-company`

```
id, universalName, linkedinUrl, name, tagline, website, logo
foundedOn{year}, employeeCount, employeeCountRange{start,end}, followerCount
description, companyType, phone
locations[]     { country, geographicArea, city, line1, headquarter, description, parsed{} }
specialities[], industries[]
logos[]         { url, width, height, expiresAt }
backgroundCovers[]
fundingData     { fundingRoundListCrunchbaseUrl,
                  lastFundingRound { fundingType, moneyRaised{}, announcedOn{},
                                     leadInvestors[], numOtherInvestors,
                                     investorsCrunchbaseUrl },
                  companyCrunchbaseUrl, numFundingRounds, updatedAt }
```

> ⚠️ **`logos[].expiresAt`** — las URLs de media de LinkedIn están firmadas y expiran (los valores observados ya estaban vencidos). Si el gem cachea empresas, debe re-obtener las imágenes, no persistir esas URLs.

> `fundingData` viene de Crunchbase, no de LinkedIn. Puede venir vacío para empresas sin rondas registradas.
