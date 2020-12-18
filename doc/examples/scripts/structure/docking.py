"""
Docking biotin to streptavidin
==============================

Lore ipsum...
"""

# Code source: Patrick Kunzmann
# License: BSD 3 clause

import numpy as np
import matplotlib.pyplot as plt
from scipy.stats import spearmanr
import biotite.structure as struc
import biotite.structure.info as info
import biotite.structure.io.mmtf as mmtf
import biotite.structure.graphics as graphics
import biotite.database.rcsb as rcsb
import biotite.application.autodock as autodock


mmtf_file = mmtf.MMTFFile.read(rcsb.fetch("2RTG", "mmtf"))
structure = mmtf.get_structure(
    # Include formal charge for accurate partial charge calc
    mmtf_file, model=1, include_bonds=True, extra_fields=["charge"])
structure = structure[structure.chain_id == "B"]
receptor = structure[struc.filter_amino_acids(structure)]
ref_ligand = structure[structure.res_name == "BTN"]
ref_ligand_center = struc.centroid(ref_ligand)

ligand = info.residue("BTN")

app = autodock.VinaApp(ligand, receptor, ref_ligand_center, [10, 10, 10])
# For reproducibility
app.set_seed(0)
# This is the maximum number:
# Vina may find less interesting binding modes
# and thus output less models
app.set_number_of_models(100)
# Effectively no limit
app.set_energy_range(100.0)
app.start()
app.join()
docked_coord = app.get_coord()
energies = app.get_energies()

docked_ligand = struc.from_template(ligand, docked_coord)
docked_ligand = docked_ligand[
    ..., ~np.isnan(docked_ligand.coord[0]).any(axis=-1)
]
docked_ligand = docked_ligand[
    ..., np.isin(docked_ligand.atom_name, ref_ligand.atom_name)
]
docked_ligand = docked_ligand[..., info.standardize_order(docked_ligand)]
ref_ligand = ref_ligand[np.isin(ref_ligand.atom_name, docked_ligand.atom_name)]
ref_ligand = ref_ligand[info.standardize_order(ref_ligand)]

# Calculate the RMSD of the docked models to the correct binding mode
# No superimposition prior to RMSD calculation, as we want to see 
# conformation differences with respect to the binding pocket
rmsd = struc.rmsd(ref_ligand, docked_ligand)

# Evaluate correlation between RMSD and binding energies 
correlation, p_value = spearmanr(energies, rmsd)
print(correlation)
print(p_value)

figure, ax = plt.subplots(figsize=(8.0, 6.0))
ax.set_title(f"$r_s$ = {correlation:.2f} ($p$ = {p_value*100:.1f}%)")
ax.scatter(energies, rmsd, marker="+", color="black")
ax.set_xlabel("Energy (kcal/mol)")
ax.set_ylabel("RMSD (Å)")
figure.tight_layout()

########################################################################
# For this specific case *AutoDock Vina* shows a low but significant
# correlation between the RMSD of the calculated models to the correct
# binding mode and the associated calculated binding energy.
# A high correlation is desireable to ensure that docking results with
# good binding energies correspond to the correct binding mode for cases
# in which the correct binding conformation is unknown.
# Most importantly, the calculated model with the lowest energy is also
# the conformation with the lowest deviation from the experimental
# result in this instance.
#
# In a final step, we want to visually compare the experimentally
# determined conformation of biotin in the binding pocket with the
# minimum-energy docked conformation, which is also the conformation
# with the lowest RMSD in this case. 


best_model = docked_ligand[np.argmin(rmsd)]

ref_ligand.bonds = struc.connect_via_residue_names(ref_ligand)
ref_ligand.res_id[:] = 1
best_model.res_id[:] = 2
merged = ref_ligand + best_model

# Color by element, except the C-atoms, which are colored by molecule
colors = np.zeros((merged.array_length(), 3))
colors[merged.element == "H"] = (0.8, 0.8, 0.8) # Gray
colors[merged.element == "N"] = (0.0, 0.0, 0.8) # Blue
colors[merged.element == "O"] = (0.8, 0.0, 0.0) # Red
colors[merged.element == "S"] = (0.8, 0.8, 0.0) # Yellow
# Green for reference ligand carbon atoms
colors[(merged.element == "C") & (merged.res_id == 1)] = (0.0, 0.8, 0.0)
# Cyan for docked ligand carbon atoms
colors[(merged.element == "C") & (merged.res_id == 2)] = (0.0, 0.8, 0.8)

fig = plt.figure(figsize=(8.0, 8.0))
ax = fig.add_subplot(111, projection="3d")
graphics.plot_atoms(
    ax, merged, colors, line_width=3, background_color="white",
    zoom=1.5
)
fig.tight_layout()
plt.show()