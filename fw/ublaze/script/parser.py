# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Environment
# ==============================================================================================

import os           # OS functions
import sys          # Manage errors
import warnings     # Manage warning

import subprocess   # Fetch the output from bash command
import fnmatch      # Match with filters
import pathlib      # Get current file path

import jinja2       # Template generator
import stat

# Checks that environment variable is available
if not(os.getenv("PROJECT_DIR")):
    sys.exit("ERROR> Environment variable $PROJECT_DIR not defined.")

# Paths
BLOCK_DIR = "fw/gen/" + os.environ["MICROBLAZE_CONF"] + "/rtl"
SIM_DIR_A = "fw/gen/" + os.environ["MICROBLAZE_CONF"] + "/ip_" + os.environ["MICROBLAZE_CONF"] + "/prj/project_microblaze.gen/sources_1/bd/ublaze/ip"
SIM_DIR_B = "fw/gen/" + os.environ["MICROBLAZE_CONF"] + "/ip_" + os.environ["MICROBLAZE_CONF"] + "/prj/project_microblaze.gen/sources_1/bd/ublaze/ipshared"

TEMPLATE_SIM_PATH = "fw/ublaze/script/simu_file_list.j2"
TEMPLATE_RTL_PATH = os.environ["PROJECT_DIR"] + "/hw/script/create_module/templates/ip_file_list_fw.j2"

FILELIST_SIM_PATH = os.environ["PROJECT_DIR"] + "/fw/gen/" + os.environ["MICROBLAZE_CONF"] + "/simu/info/file_list.json"
FILELIST_RTL_PATH = os.environ["PROJECT_DIR"] + "/fw/gen/" + os.environ["MICROBLAZE_CONF"] + "/info/file_list.json"

# -------------------------------------------------------------------------------------------------------------------- #
# Parser for Block design configurations
# -------------------------------------------------------------------------------------------------------------------- #
# initializing lists
bd_list = []
bd_sim_list_a = []
bd_sim_list_b = []
bd_sim_list = []
bd_inc_list = []
xci_list = []

# Searching for the different block design names
# These are the ones defined directly by vivado generation
print("> Found Block design :")
for root, dirnames, filenames in os.walk(BLOCK_DIR, topdown=False):
   for filename in dirnames:
        bd_list.append(os.path.join(filename))
        print("  > " + os.path.join(filename))

for root, dirnames, filenames in os.walk(BLOCK_DIR, topdown=False):
    for filename in fnmatch.filter(filenames, '*.xci*'):
        xci_list.append(os.path.join(root, filename))
    for filename in fnmatch.filter(filenames, '*.v*'):
        xci_list.append(os.path.join(root, filename))

print("\n")

# Searching for simulation sources
# There are two types :
# 1 - Simulation source from block design
i = 0
while i < len(bd_list):
    proc = subprocess.Popen(["find " + SIM_DIR_A + ' -wholename '+'"*/sim/' + bd_list[i] + '.v*"'], stdout=subprocess.PIPE, shell=True)
    (out, err) = proc.communicate()
    # print(out.decode('utf-8').strip())
    bd_sim_list_a.append(out.decode('utf-8').strip())

    # it's most likely that some items from the block design list 'bd_list' are missing
    # They'll be in 'bd_sim_list_b' instead. We need to remove empty elements in case this happens.
    bd_sim_list_a = ' '.join(bd_sim_list_a).split()
    i = i +1

# 2 - Simulation sources from vivado shared ip
for root, dirnames, filenames in os.walk(SIM_DIR_B):
    for filename in fnmatch.filter(filenames, '*.v'):
        bd_sim_list_b.append(os.path.join(root, filename))
    for filename in fnmatch.filter(filenames, '*.vh'):
        bd_inc_list.append(os.path.join(root, filename))

bd_sim_list = bd_sim_list_a + bd_sim_list_b

print("> Simulation sources :")
i = 0
while i < len(bd_sim_list):
    print("  > " + bd_sim_list[i])
    i=i+1

print("\n")

# -------------------------------------------------------------------------------------------------------------------- #
# Writing Filelists
# -------------------------------------------------------------------------------------------------------------------- #
if (os.path.exists(FILELIST_SIM_PATH)):
    warnings.warn("WARNING> File {:s} already exists".format(FILELIST_SIM_PATH))
else:
    with open(TEMPLATE_SIM_PATH) as file_:
        template_sim = jinja2.Template(file_.read())
    with open(FILELIST_SIM_PATH, 'w') as fp:
        fp.write(template_sim.render({'simulation_list': bd_sim_list, 'include_list': bd_inc_list,'microblaze_conf': os.environ["MICROBLAZE_CONF"]}))
    print(" => Simulation File list successfully written")

if (os.path.exists(FILELIST_RTL_PATH)):
    warnings.warn("WARNING> File {:s} already exists".format(FILELIST_RTL_PATH))
else:
    with open(TEMPLATE_RTL_PATH) as file_:
        template_hdl = jinja2.Template(file_.read())
    with open(FILELIST_RTL_PATH, 'w') as fp:
        fp.write(template_hdl.render(ip_list=xci_list))
    print(" => Design File list successfully written")

print("\n")
