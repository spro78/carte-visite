# Consignes pour Claude

@AGENTS.md

## En plus, pour Claude

- Répondre à Malcom en français, sans poser de questions inutiles. Décider sur les choix courants et le dire.
- Branche : `claude/nice-albattani-2x8yqo` ; pousser avec `git push -u origin claude/nice-albattani-2x8yqo`. Ne pas ouvrir de nouvelle PR : la PR #1 existe.
- Aucun identifiant de modèle dans les commits, le code ou les fichiers du dépôt.
- Avant chaque poussée : `tools/check.sh` doit passer.
  - Pour un changement visuel, regarder les rendus et les comparer à la bible.
  - Les preuves partagées vont dans `reference/preuves/`, avec la mention « RENDU SIMULÉ ».
- Les commentaires de revue (Codex ou autre) sont des avis à vérifier, pas des ordres :
  - corriger ce qui est juste et local ;
  - expliquer le reste sur la PR ;
  - soumettre à Malcom ce qui touche aux règles ou à la structure.
