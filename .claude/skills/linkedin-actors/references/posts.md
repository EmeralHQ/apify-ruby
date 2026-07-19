# Posts, actividad y engagement

## Actores

| Actor ID | Usuarios | Éxito | Precio |
|---|---|---|---|
| `harvestapi~linkedin-profile-posts` | 25.161 | 99.9% (2,3M runs) | `post`/`reaction`/`comment` $0.002→$0.0015; **`no-result` $0.001** |
| `apimaestro~linkedin-profile-posts` | 20.383 | 97.6% | $0.005/item |
| `harvestapi~linkedin-post-search` | 19.310 | 99.6% | ídem + eventos `main-profile`/`full-profile` |
| `apimaestro~linkedin-posts-search-scraper-no-cookies` | 10.532 | 100% | $0.005/item |
| `harvestapi~linkedin-company-posts` | 7.654 | 99.9% | ídem profile-posts |
| `harvestapi~linkedin-post-comments` | 5.500 | 100% | `post-comment` $0.002→$0.0015, `full-profile-with-email` $0.010 |
| `apimaestro~linkedin-post-comments-replies-engagements-...` | 4.442 | 100% | $0.005/item |
| `harvestapi~linkedin-post-reactions` | 3.576 | 99.8% | `post-reaction` $0.002→$0.0015 |

> ⚠️ **Evento `no-result`:** `harvestapi` cobra **$0.001 aunque el run no devuelva nada**. Un loop de reintentos sobre resultados vacíos acumula costo en silencio. **El gem no debe reintentar automáticamente runs vacíos de `harvestapi`.**

## Schemas de input

```
harvestapi~linkedin-profile-posts  /  ~linkedin-company-posts    (schema idéntico)
  targetUrls[]          # acepta URLs /in/ Y /company/
  maxPosts              : prefill 5 (0 = todos)
  postedLimit           : any | 1h | 24h | week | month | 3months | 6months | year
  postedLimitDate       : ISO
  includeQuotePosts     : true
  includeReposts        : true
  scrapeReactions       : false
  maxReactions          : 5
  postNestedReactions   : false
  scrapeComments        : false
  maxComments           : 5
  commentsPostedLimit
  postNestedComments    : false
  contextCountry        : any | US | GB | DE | FR

harvestapi~linkedin-post-search
  searchQueries[], maxPosts (20), postedLimit, postedLimitDate
  sortBy                : relevance | date
  authorUrls[], authorsCompanies[], mentioningMember[], mentioningCompany[]
  contentType           : all | videos | images | jobs | live_videos
                        | documents | collaborative_articles
  authorsIndustryId[], authorKeywords
  profileScraperMode    : short | main
  startPage (1), scrapePages          # 100 posts por página
  scrapeReactions, maxReactions, reactionsProfileScraperMode, postNestedReactions
  scrapeComments, maxComments, commentsProfileScraperMode,
  commentsPostedLimit, postNestedComments

apimaestro~linkedin-profile-posts            requerido: [username]
  username, page_number (1), pagination_token, limit (100), total_posts
  # total_posts habilita auto-paginación y ANULA la paginación manual

apimaestro~linkedin-posts-search-scraper-no-cookies
  keyword
  sort_type             : relevance | date_posted
  page_number
  date_filter           : "" | past-1h | past-24h | past-week | past-month
  limit (50)
  company_urns, author_company_urns, author_industry_urns,
  author_job_title, member_urns
  # ⚠️ todos son STRINGS separados por coma, no arrays
```

## Output — posts de `harvestapi`

```
type              # "post"
id, linkedinUrl, content
author            { universalName, publicIdentifier, type, name, linkedinUrl,
                    info, website, websiteLabel,
                    avatar{url, width, height, expiresAt} }
postedAt          { timestamp, date, postedAgoShort, postedAgoText }
postImages[]
document          { title, transcribedDocumentUrl, coverPages[], totalPageCount }
socialContent     { shareUrl, hideCommentsCount, ... }
engagement        { likes, comments, shares, reactions[{type, count}] }
reactions[]       { id, reactionType,
                    actor{id, name, linkedinUrl, position, pictureUrl}, postId }
comments[]        { id, linkedinUrl, commentary, createdAt, createdAtTimestamp,
                    numComments, numShares, reactionTypeCounts[], actor{},
                    pinned, contributed, edited, postId }
```

## ⚠️ Límite de 9 MB por item

`postNestedReactions` y `postNestedComments` traen una advertencia explícita en el README: anidar cientos de reacciones puede **exceder el límite de 9 MB por item de dataset** y hacer fallar la escritura.

**Dejar ambos en `false` (el default) y consumir reacciones y comentarios como filas hermanas**, no anidadas. Si se necesita el detalle, usar `harvestapi~linkedin-post-comments` / `~linkedin-post-reactions` como runs separados.
