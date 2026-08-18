#!/usr/bin/env bash
set -euo pipefail

DESIGN="$1"

RTL="rtl/${DESIGN}.sv"
LIBERTY="lib/NangateOpenCellLibrary_typical.lib"
NETLIST="results/${DESIGN}_netlist.v"
SYNTH_LOG="results/${DESIGN}_synth.log"
STA_LOG="results/${DESIGN}_sta.log"
SDC="constraints/mac.sdc"

mkdir -p results

echo "=== Synthesizing ${DESIGN} ==="

yosys -p "
    read_verilog -sv ${RTL}
    hierarchy -check -top ${DESIGN}

    proc
    opt
    fsm
    opt
    memory
    opt

    techmap
    opt

    dfflibmap -liberty ${LIBERTY}
    abc -liberty ${LIBERTY}

    clean
    stat -liberty ${LIBERTY}

    write_verilog -noattr -noexpr ${NETLIST}
" | tee "${SYNTH_LOG}"

echo
echo "=== Running STA for ${DESIGN} ==="

sta <<EOF | tee "${STA_LOG}"
read_liberty ${LIBERTY}
read_verilog ${NETLIST}
link_design ${DESIGN}
read_sdc ${SDC}
report_checks -path_delay max -fields {slew cap input_pins} -digits 3
EOF