# Empleos

Es la categoría más competida y la de mejor precio por item. `curious_coder~linkedin-jobs-scraper` es el actor de LinkedIn más usado de toda la plataforma.

## Actores

| Actor ID | Usuarios | Éxito 30d | Precio | Nota |
|---|---|---|---|---|
| `curious_coder~linkedin-jobs-scraper` | **117.621** | 98.8% | $0.001/item | El más usado |
| `cheap_scraper~linkedin-job-scraper` | 30.002 | 96.8% | arranque $0.005 + **$0.0007→$0.00035** | Filtros más ricos; **mínimo 150 resultados facturables** |
| `bebity~linkedin-jobs-scraper` | 34.685 | 98.8% | **RENTAL $29.99/mes** | Tarifa plana, 4.320 min de prueba |
| `worldunboxer~rapid-linkedin-scraper` | 13.419 | 98.3% | $0.0005→$0.00045 | |
| `valig~linkedin-jobs-scraper` | 9.977 | 99.6% | **$0.0004→$0.00028** | Más barato + interfaz más limpia |
| `fantastic-jobs~advanced-linkedin-job-search-api` | 9.651 | 99.9% | $0.005→$0.0015 | Enriquecido con IA, ~45 filtros |
| `apimaestro~linkedin-jobs-scraper-api` | 4.435 | 100% | $0.005/item | |

**Recomendación:** `valig~linkedin-jobs-scraper` como primario — es el más barato, tiene 99.6% de éxito y la interfaz tipada más limpia. Además es de los **dos únicos actores de LinkedIn cuyo timeout por defecto (300s) cabe en el endpoint sync**.

## Schemas de input

```
curious_coder~linkedin-jobs-scraper          requerido: [urls]
  urls[]            # URLs de búsqueda de LinkedIn (usar incógnito para obtener la forma pública)
  scrapeCompany     : bool (default true)   # request extra por empleo — más lento
  count             : int (prefill 100)
  splitByLocation   : bool
  splitCountry      : enum US,CA,MX,GB,DE,...
  # splitByLocation está documentado como workaround al tope de 1000 empleos por URL de búsqueda

valig~linkedin-jobs-scraper                  # la interfaz tipada más limpia
  title, location
  datePosted        : "" | r2592000 (30d) | r604800 (7d) | r86400 (24h)
  companyName[], companyId[], contractType[], experienceLevel[], remote[]
  limit             : default 100
  urlPath, urlParam (keyValue), skipJobId[]

apimaestro~linkedin-jobs-scraper-api         # snake_case
  keywords, company_id
  location          : default "Worldwide"
  page_number
  remote            : "" | onsite | remote | hybrid
  sort              : "" | relevant | recent
  date_posted       : "" | month | week | day
  experienceLevel   : "" | internship | entry | associate | mid_senior | director | executive
  easy_apply, under_10_applicants
  limit             : 1-100

cheap_scraper~linkedin-job-scraper           # ~35 campos; startUrls[] O keyword[]+locations[]
  keyword[], locations[], location, distance ("5".."50"), publishedAt
  jobType[], experienceLevel[], workType[], salaryBase
  companyInclude[]/companyExclude[], jobTitleExclude[], subLocationExclude[]
  jobFunctionInclude[]/Exclude[], jobIndustryInclude[]/Exclude[]
  companySizeMin/Max, companyFoundedDateMin/Max, companyFollowersCountMin/Max
  companyOrganizationTypeInclude[]/Exclude[]
  excludeRecruitingAgencies, requireRecruiterProfile, requireSalaryInfo,
  filterUnder10Applicants, filterEasyApply
  resumeKeywords[{keyword, aliases[]}]
  maxItems, saveOnlyUniqueItems, enrichCompanyData
```

## Output — `curious_coder~linkedin-jobs-scraper`

```
id, link, title, companyName, companyLinkedinUrl, companyLogo, location
salaryInfo[], postedAt, benefits[], descriptionHtml, descriptionText
applicantsCount, applyUrl
jobPosterName, jobPosterTitle, jobPosterPhoto, jobPosterProfileUrl
seniorityLevel, employmentType, jobFunction, industries
companyDescription, companyWebsite, companyEmployeesCount
```

## Output — `cheap_scraper~linkedin-job-scraper`

```
jobId, jobTitle, location, salaryInfo[], postedTime, publishedAt, searchString
jobUrl, companyName, companyUrl, companyLogo, companyId
jobDescription, applicationsCount, contractType, experienceLevel, yearsOfExperience
workType, sector, applyUrl, applyType, posterFullName, posterProfileUrl
dynamicFilterMatch

# con resumeKeywords:
matchedKeywords[], unmatchedKeywords[], keywordMatchScorePercentage

# con enrichCompanyData:
companyDescription, companyEmployeeCount, companyEmployeeCountRange, companyWebsite,
companyIndustry, companyOrganizationType, companyFoundedDate, companySpecialties[],
companyFollowersCount, companyOfficeLocations[], companyAffiliatedPages[],
companyRecentPosts[],
companyAddress { streetAddress, addressLocality, addressRegion, postalCode, addressCountry }
```

## ⚠️ Trampas de facturación de `cheap_scraper`

1. **`dynamicFilterMatch` marca, no filtra.** Varios filtros (`excludeRecruitingAgencies`, `companySizeMin/Max`, `requireSalaryInfo`, excludes de tipo de organización) **no filtran** — solo marcan la fila con `dynamicFilterMatch: false`. Las filas igual se recolectan **y se facturan**.

2. **Mínimo de 150 resultados facturables.** Combinado con lo anterior, una consulta chica y muy filtrada puede costar mucho más de lo esperado.

Si el uso es de volumen bajo o muy filtrado, `valig` sale más barato pese a tener menos filtros.

## Cap estructural de LinkedIn

LinkedIn devuelve **máximo ~1000 empleos por URL de búsqueda**. No se sortea subiendo `limit` — hay que segmentar la consulta (por eso existe `splitByLocation` en `curious_coder`). Ver la nota de segmentación en [people-search.md](people-search.md).
