# Kit importé dans Studio (à déposer ici)

Ce dossier devient `ServerStorage` dans la place construite par Rojo.

1. Dans Studio, importer `assets/kit/HoH_Kit.fbx` (*Import 3D*). Studio crée un modèle **HoH_Kit** rempli de MeshParts.
2. Clic droit sur **HoH_Kit** > *Save to File…* > enregistrer **HoH_Kit.rbxm** dans ce dossier.
3. Pousser le fichier sur la branche. Toutes les places suivantes contiennent alors les vrais meshes : plus aucun mesh n'est construit par les joueurs, donc plus de limite mémoire.

Le jeu trouve le kit tout seul (`Kit.Init`, sortie : `[Kit] Kit importé trouvé (HoH_Kit) : 189/189 pièces`).
Après un changement du kit (`tools/assets/build.sh`), refaire l'import.
