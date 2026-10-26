# PC COMMAND — Research / counter-research notes

## Standards retenus
1. **CloudEvents**: utiliser un envelope d'evenement stable (id/source/type/time/data) au lieu de logs libres.
2. **W3C Trace Context**: utiliser un identifiant de trace pour correler une conversation a travers plusieurs composants.
3. **OpenTelemetry**: traiter chaque operation comme un span pouvant porter des evenements, attributs, parentage et statut.
4. **Process mining**: considerer une conversation comme un case/trace et les actions comme des evenements horodates; un evenement nouveau peut forcer l'ajustement du modele.

## Ce qui n'est PAS retenu
- Pas de stack OpenTelemetry complete locale: trop lourde pour 4 Go et inutile pour l'objectif.
- Pas de Kafka/Redis/Elastic/Prometheus/Grafana: infrastructure disproportionnee et incompatible avec le budget zero.
- Pas de modele IA local resident: RAM insuffisante et decision BCP deja opposee a un AI-NODE.
- Pas de surveillance magique des conversations ChatGPT: aucune API de compte exposee au PowerShell pour cela.
- Pas de progression basee sur le temps seulement: cela creerait un faux avancement.

## Reemploi minimal
On reprend les idees, pas les stacks:
- CloudEvents -> schema JSON compact.
- Trace Context -> trace_id/span_id.
- OTel -> parentage + events + status.
- Process mining -> event log + reconstruction + conformance.
- Event sourcing -> faits append-only + projection d'etat.
