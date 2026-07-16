# Recherche — APIs de facturation (pour générer des factures depuis les heures trackées)

> Notes de recherche (16 juillet 2026). À reprendre plus tard pour une éventuelle
> intégration « générer une facture depuis les entrées d'un projet/mois ».

## TL;DR
- **Meilleur choix si compte Qonto** → **Qonto Business API** : API mûre, création de
  factures conforme (FR), EUR natif, modèle `items` qui calque exactement les données
  de clockapp (quantité = heures, prix unitaire = taux horaire).
- **Meilleur choix DIY / gratuit** → **Invoice Ninja** : REST complet, open-source,
  auto-hébergeable, pas de paywall API.
- **Zervant** (le point de départ de la question) : ❌ pas d'API publique exploitable
  (racheté par SumUp ; aucune doc de référence).

## Comparatif

| Outil | API publique ? | Note |
|---|---|---|
| **Qonto** | ✅ Oui, création de factures | Compte bancaire pro requis. Voir détails ci-dessous. |
| **Invoice Ninja** | ✅ Oui, complète + open-source | Auto-hébergeable = gratuit. Le plus « hackable ». |
| **Sellsy** | ✅ API ouverte (FR) | Suite CRM+facturation mûre. |
| **Abby** | ✅ API tierce | Profil micro-entrepreneur / URSSAF (proche du profil de Jules). Vérifier self-serve vs sur demande. |
| **Pennylane / Tiime / Indy** | ⚠️ API souvent orientée partenaires | « Plateformes agréées » e-facture ; peut nécessiter validation. |
| **Stripe Invoicing** | ✅ Excellente API | Top si on veut aussi encaisser le paiement ; factures plus basiques. |
| **Henrri** | ❌ Pas d'API | Explicitement sans API. |
| **Freebe** | ❔ Pas d'API publique claire | Bon outil FR freelance, pas de doc dev trouvée. |
| **Zervant** | ❌ Pas d'API exploitable | À écarter comme cible d'intégration. |

## Qonto Business API — détails
- **Base URL** : `https://thirdparty.qonto.com/v2` (sandbox : `https://thirdparty-sandbox.staging.qonto.co/v2`)
- **Auth** : clé API (Bearer) ou OAuth 2.0 ; portail dev `developers.qonto.com` ; webhooks temps réel.
- **Ressources facturation** : factures client (créer / finaliser / lister / récupérer),
  clients (créer), devis, avoirs, factures fournisseur.
- **Plateforme agréée** e-facture → aligné avec la réforme française de sept. 2026.
- **Collection Postman** officielle dispo pour tester sans coder.

### Créer une facture — `POST /v2/client_invoices`
Champs clés : `client_id`, `issue_date`, `due_date`, `currency`, `payment_methods`,
et `items[]` avec `title`, `quantity`, `unit_price`, `vat_rate`, `discount`.

Mapping direct depuis clockapp :
```jsonc
{
  "client_id": "…",
  "issue_date": "2026-07-31",
  "due_date": "2026-08-30",
  "currency": "EUR",
  "items": [
    { "title": "Projet ACME – dev",   "quantity": "42.5", "unit_price": "50.00", "vat_rate": "0" },
    { "title": "Projet GLOBEX – API", "quantity": "12.0", "unit_price": "60.00", "vat_rate": "0" }
  ]
}
```
- `quantity` = heures trackées, `unit_price` = taux horaire, un **item par projet**
  (le regroupement par projet existe déjà dans l'app), `vat_rate: 0` si franchise en base.

### Nuances importantes
- **Compte Qonto requis** (c'est une banque pro) ; accès API via le portail développeur.
- **Flux draft → finalize** : la facture se crée en brouillon puis se **finalise** via un
  endpoint séparé (`finalize-a-client-invoice`) — pour la numérotation séquentielle légale
  française. Permet de vérifier avant émission définitive.

### Piste d'implémentation (plus tard)
Un `QontoInvoiceService.swift` : créer/retrouver le client → construire les `items` depuis
les entrées d'un projet sur une période → `POST` brouillon → (optionnel) finaliser.
Tester d'abord en **sandbox**.

## Contexte réglementaire
Facturation électronique via **plateformes agréées** obligatoire en France à partir de
**septembre 2026** → privilégier un outil agréé (Qonto, Sellsy, Pennylane, Tiime, Indy…)
plutôt que des PDF « libres ».

## Sources
- Qonto — Créer une facture client : https://docs.qonto.com/api-reference/business-api/expense-management/client-quotes-notes/client-invoices/create-a-client-invoice
- Qonto — Finaliser une facture : https://docs.qonto.com/api-reference/business-api/expense-management/client-quotes-notes/client-invoices/finalize-a-client-invoice
- Qonto — Créer un client : https://docs.qonto.com/api-reference/business-api/clients/create-a-client
- Qonto — Overview Business API : https://docs.qonto.com/get-started/business-api/overview
- Qonto — Collection Postman : https://www.postman.com/qontoteam/qonto-public-api/collection/ptsif4n/qonto-business-api
- Invoice Ninja — API : https://api-docs.invoicing.co/
- apitracker — Zervant : https://apitracker.io/a/zervant
