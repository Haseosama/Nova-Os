# NovaOS Studio

Interface locale de préparation d’un kit de personnalisation Windows, au thème sombre et futuriste.

## Lancer l’interface

Aucune dépendance ni compilation n’est nécessaire. Depuis ce dossier :

```bash
python3 -m http.server 4173 --bind 0.0.0.0
```

Puis ouvrez `http://localhost:4173` (ou le lien de prévisualisation fourni par l’environnement).

## Fonctionnalités

- Sélection et glisser-déposer d’un fichier `.iso` ; seul son nom et sa taille sont affichés. Le contenu n’est ni lu ni téléversé.
- Profils Nova Clean, Essentiel et Sur mesure, avec réglages système, confidentialité et applications.
- Choix de langue/clavier, thème sombre ou clair et couleur d’accentuation.
- Export local d’une archive ZIP contenant un profil JSON, un script PowerShell commenté, un fichier de réponse langue/clavier et un guide.
- Historique de session, navigation responsive et aperçu visuel du premier démarrage.

## Limites importantes

L’export est un **kit de configuration, pas un ISO Windows reconstruit**. Le navigateur ne monte pas et ne modifie pas le média source. Pour reconstruire une image, il faut un poste Windows, un processus de maintenance adapté (par exemple DISM) et les outils Windows ADK. Le script généré demande une confirmation explicite, propose un mode `-PreviewOnly` et doit être relu/testé dans une machine virtuelle avant usage.

Windows peut conserver des diagnostics requis selon l’édition et les stratégies de l’organisation ; le projet ne promet pas une télémétrie nulle. Les mises à jour, Defender, Edge, le Microsoft Store, l’activation, le compte Microsoft et les exigences matérielles ne sont pas supprimés ni contournés.
