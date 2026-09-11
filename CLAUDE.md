# CLAUDE.md

Mémoire partagée du projet ISAI Sourcing. **Toute session Claude (Cowork ou Claude Code) qui travaille sur un des 3 repos doit lire ce fichier en démarrant, et ajouter une ligne au journal d'avancement en bas après un changement notable** (décision, bug corrigé, piège découvert, feature livrée). La section "Vue d'ensemble" et le "Journal d'avancement" sont dupliqués à l'identique dans les 3 repos (back/front/pipeline) — répercuter tout ajout dans les 3 fichiers pour rester synchronisé.

## Vue d'ensemble du système

Le projet ISAI Sourcing (outil de sourcing investissement pour l'équipe ISAI) est réparti sur 3 repos GitHub (org `ISAIVC`) qui fonctionnent ensemble :

- **`isai-sourcing-front`** — dashboard React 19 / Vite / Chakra UI 3. Les analystes y consultent et filtrent les sociétés, lancent des recherches sémantiques/concurrents, poussent vers Attio, déclenchent le pipeline d'ingestion.
- **`isai-sourcing-back`** — Supabase (Postgres + Auth + RLS + Edge Functions Deno). Source de vérité du schéma, des vues (`sourcing_view`, `sourcing_mv`) et des fonctions SQL de matching (recherche floue, similarité vectorielle).
- **`isai-sourcing-pipeline`** — Python / Prefect / Terraform. Scrape, enrichit (LLM, embeddings) et score les sociétés ; écrit dans les mêmes tables Supabase. Orchestré par Prefect Cloud, tourne sur AWS ECS (Terraform), déployé par GitHub Actions.

**Flux type** : front (page Ingestion) → edge function `run-prefect-pipeline` → déploiement Prefect Cloud → tâches sur ECS → écriture dans Supabase → front relit `sourcing_view`/`sourcing_mv`.

Projet Supabase principal : ref `blfkamqmdmgkykcjyopd` (voir aussi note dans la section back sur un second ref rencontré pour les secrets Prefect — à clarifier).

## Ce repo : isai-sourcing-back

Migrations SQL (`supabase/migrations/*.sql`, **non horodatées** — l'ordre alphabétique ne respecte pas les dépendances, ex. `functions.sql` référence `sourcing_mv.sql`) + Edge Functions Deno (`supabase/functions/*`).

**Fonctions actuellement dans le repo** : `assess-db-changes-from-traxcn-export`, `classify-landscape`, `query-with-semantic-search`, `run-prefect-pipeline`, `parse-free-text-query`, `push-to-attio`. (Le `README.md` mentionne aussi `create-onepager` : elle n'existe plus dans le repo — README obsolète sur ce point.)

**Déploiement** : push sur `main` → GitHub Actions déploie les edge functions. **Les migrations SQL ne sont PAS appliquées automatiquement** — la CI ne déploie que les edge functions. Chaque migration doit être copiée-collée manuellement dans le SQL Editor du dashboard Supabase.

### Convention à respecter

**Toute nouvelle table doit avoir une policy RLS**, sinon RLS bloque silencieusement tout accès (échec générique côté front du type "Failed to create X"). Après `CREATE TABLE` :

```sql
alter table public.<table> enable row level security;
create policy "Allow all for authenticated"
  on public.<table> for all to authenticated
  using (true) with check (true);
```

L'app exige une connexion, donc une policy `authenticated` seule suffit (pas besoin d'ouvrir à `anon`).

### Feature : recherche de concurrents (`match_competitors`)

Fonction SQL `SECURITY DEFINER` qui compare l'embedding `solution_and_use_cases_embedding` (pas `full_embedding`, qui rapproche par discours marketing plutôt que par ce que fait vraiment la boîte) de la société source à toutes les autres par distance cosine, filtre sous `p_min_similarity = 0.5` (**non calibré**, à ajuster à l'usage), puis rejoint `sourcing_mv`. Appelée directement par le front (mode concurrents dans `HomePage.jsx`, bouton dans `CompanySidePanel.jsx`).

- Pas d'index vectoriel sur cet axe → ~14s/recherche (comparaison à toute la table). Un index HNSW réglerait ça mais sa construction dépasse le timeout de l'éditeur SQL du dashboard (il faudrait un `psql` direct) — pas fait à ce jour.
- `statement_timeout` du rôle `authenticated` relevé à 30s (le défaut de 8s tuait la requête).
- Évolution envisagée : reranking Cohere sur les 200 plus proches voisins (edge function + clé Cohere côté serveur) ; croisement avec `competitors_cg`/`competitors_by` (Tracxn) pour badger les concurrents confirmés par les deux sources.

### Dette technique connue (audit du 13/07/2026 — statut de correction non suivi depuis)

- 🔴 Les 5 edge functions sont déployées avec `--no-verify-jwt` et ne vérifient pas l'auth dans leur code → accessibles sans authentification depuis Internet (lecture DB via service role, push Attio, déclenchement pipeline).
- 🔴 Tables `crunchbase_*`/`traxcn_*` : policies `FOR SELECT USING (true)` sans `TO authenticated` → lisibles par le rôle `anon`, exposent emails/téléphones (sujet RGPD).
- 🟠 `get_distinct_values` (`SECURITY DEFINER`) exécutable par `anon`, sans `search_path` fixé.
- 🟠 Virgule manquante dans `main_tables.sql` (~lignes 106-107 et 155-156) invaliderait les contraintes UNIQUE de `funding_rounds`/`founders` si le fichier était rejoué tel quel — si la prod fonctionne, le repo ne reflète pas l'état réel de la prod.
- 🟡 `update_updated_at_column` définie 3 fois avec des versions différentes (search_path protégé ou non) selon le fichier exécuté en dernier.
- Détail complet (avec toutes les sévérités) : `AUDIT.md` section 1, dans le dossier local `Datadriven_sourcing` (pas encore versionné).

### À vérifier / zone d'ombre

Deux refs de projet Supabase rencontrées dans des contextes différents : `blfkamqmdmgkykcjyopd` (README, secrets GitHub Actions) et `nhszmpinlumqrfnrflrm` eu-west-3 (secrets d'edge functions liés à Prefect, vus le 25/08/2026). À clarifier : même projet renommé/redémarré, ou deux projets Supabase distincts ?

## Journal d'avancement (partagé — dupliqué dans les 3 repos, garder synchronisé)

Ajoutez une ligne datée à chaque décision, bug corrigé, ou piège découvert. Une phrase courte + fichier concerné si utile.

- **2026-07-13** — Audit complet sécurité/qualité des 3 repos (voir `AUDIT.md`/`AUDIT_FRONT.md`, pour l'instant uniquement dans le dossier local `Datadriven_sourcing`, pas versionné). 5 actions prioritaires identifiées : JWT sur les edge functions, fermer l'accès `anon` aux tables Crunchbase/Tracxn, fermer l'ingress ECS, fiabiliser Attio/pagination pipeline, introduire des tests.
- **2026-08-06** — Piège découvert : une nouvelle table Supabase sans policy RLS bloque silencieusement tout accès front.
- **2026-08-25** — Incident : ingestion Tracxn cassée par un header row qui diffère par feuille (workaround manuel appliqué, fix propre pas encore fait) ; clé API Prefect Cloud expirée a cassé le déclenchement du pipeline depuis le front (401) — procédure de rotation documentée (3 emplacements).
- **2026-08-25** — Mesure : le mode auto du business processing ne converge pas (2520/72407 domaines sans embedding) ; le scoring `solution_fit` (1-NN) a des faiblesses identifiées (pas de seuil, espace anisotrope, k=1) — à mesurer avant de corriger.
- **~2026-09** — Feature livrée : recherche de concurrents par similarité vectorielle (`match_competitors`), ~14s/recherche (pas d'index HNSW), seuil de similarité 0.5 non calibré. Reranking Cohere et croisement avec `competitors_cg`/`competitors_by` envisagés en évolution.
- **2026-09-02** — Mise en place de ce `CLAUDE.md` partagé (dans les 3 repos) comme mémoire de projet versionnée, pour que Simon et son collègue (et leurs sessions Claude respectives) partagent le même contexte.
- **2026-09-11** — Feature livrée : dossiers pour les listes, en miroir de ceux des vues (table `list_folders`, colonne `folder_id` sur `saved_lists`, CRUD dans `ListContext.jsx`, UI dans `Sidebar.jsx` + sélecteur de dossier à la création dans `HomePage.jsx`). Migration `isai-sourcing-back/supabase/migrations/list_folders.sql` pas encore appliquée en base — à copier-coller manuellement dans le SQL Editor Supabase (cf. convention migrations).
