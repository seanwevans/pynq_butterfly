#!/usr/bin/env python3
from pathlib import Path

source = Path("rtl/poly_mul4096_four_butterfly_pipeline_runtime_profile_core.sv")
target = Path("rtl/poly_mul4096_four_butterfly_pipeline_runtime_profile_handoff_core.sv")

if not source.exists():
    raise SystemExit(f"missing source core: {source}")

text = source.read_text()

old_name = "module poly_mul4096_four_butterfly_pipeline_runtime_profile_core ("
new_name = "module poly_mul4096_four_butterfly_pipeline_runtime_profile_handoff_core ("
if old_name not in text:
    raise SystemExit("source module declaration not found")
text = text.replace(old_name, new_name, 1)

old_ports = '''    input  logic [11:0] read_b_addr,
    output logic [31:0] read_b_data,

    input  logic        profile_modulus_we,'''
new_ports = '''    input  logic [11:0] read_b_addr,
    output logic [31:0] read_b_data,

    /* Idle-only eight-wide result/refill handoff port. */
    input  logic              handoff_read_valid,
    input  logic [11:0]       handoff_read_base,
    output logic              handoff_read_data_valid,
    output logic [7:0][31:0]  handoff_read_data,

    input  logic              handoff_write_valid,
    input  logic [11:0]       handoff_write_base,
    input  logic [7:0][31:0]  handoff_write_a_data,
    input  logic [7:0][31:0]  handoff_write_b_data,

    input  logic        profile_modulus_we,'''
if old_ports not in text:
    raise SystemExit("read/profile port insertion point not found")
text = text.replace(old_ports, new_ports, 1)

old_decl = '''    logic [7:0][11:0] inspect_a_address;
    logic [7:0][11:0] inspect_b_address;

    integer inspect_index;'''
new_decl = '''    logic [7:0][11:0] inspect_a_address;
    logic [7:0][11:0] inspect_b_address;
    logic [7:0][11:0] handoff_read_address;
    logic [7:0][11:0] handoff_write_address;

    logic             handoff_read_valid_q;

    logic             a_store_effective_write_valid;
    logic [7:0][11:0] a_store_effective_write_address;
    logic [7:0][31:0] a_store_effective_write_data;

    logic             b_store_effective_write_valid;
    logic [7:0][11:0] b_store_effective_write_address;
    logic [7:0][31:0] b_store_effective_write_data;

    integer inspect_index;'''
if old_decl not in text:
    raise SystemExit("coefficient-store declaration insertion point not found")
text = text.replace(old_decl, new_decl, 1)

old_loop = '''            inspect_b_address[inspect_index] =
                read_b_addr ^ inspect_index[11:0];
        end

        a_store_read_valid ='''
new_loop = '''            inspect_b_address[inspect_index] =
                read_b_addr ^ inspect_index[11:0];

            handoff_read_address[inspect_index] =
                handoff_read_base + inspect_index[11:0];

            handoff_write_address[inspect_index] =
                handoff_write_base + inspect_index[11:0];
        end

        a_store_read_valid ='''
if old_loop not in text:
    raise SystemExit("address-generation insertion point not found")
text = text.replace(old_loop, new_loop, 1)

old_idle = '''        if (!busy)
        begin
            a_store_read_valid =
                1'b1;

            a_store_read_address =
                inspect_a_address;

            b_store_read_valid =
                1'b1;

            b_store_read_address =
                inspect_b_address;
        end
        else if (issue_valid)'''
new_idle = '''        if (!busy)
        begin
            a_store_read_valid =
                1'b1;

            b_store_read_valid =
                1'b1;

            if (handoff_read_valid)
            begin
                a_store_read_address =
                    handoff_read_address;

                b_store_read_address =
                    handoff_read_address;
            end
            else
            begin
                a_store_read_address =
                    inspect_a_address;

                b_store_read_address =
                    inspect_b_address;
            end
        end
        else if (issue_valid)'''
if old_idle not in text:
    raise SystemExit("idle read mux not found")
text = text.replace(old_idle, new_idle, 1)

old_read_assign = '''    assign read_b_data =
        b_store_read_data[0];

    ntt4096_eight_bank_coeff_store_runtime coefficient_store_a ('''
new_read_assign = '''    assign read_b_data =
        b_store_read_data[0];

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            handoff_read_valid_q <=
                1'b0;
        end
        else
        begin
            handoff_read_valid_q <=
                handoff_read_valid
                && !busy;
        end
    end

    assign handoff_read_data_valid =
        handoff_read_valid_q
        && a_store_read_data_valid;

    assign handoff_read_data =
        a_store_read_data;

    always_comb
    begin
        a_store_effective_write_valid =
            a_store_write_valid;

        a_store_effective_write_address =
            a_store_write_address;

        a_store_effective_write_data =
            a_store_write_data;

        b_store_effective_write_valid =
            b_store_write_valid;

        b_store_effective_write_address =
            b_store_write_address;

        b_store_effective_write_data =
            b_store_write_data;

        if (!busy && handoff_write_valid)
        begin
            a_store_effective_write_valid =
                1'b1;

            a_store_effective_write_address =
                handoff_write_address;

            a_store_effective_write_data =
                handoff_write_a_data;

            b_store_effective_write_valid =
                1'b1;

            b_store_effective_write_address =
                handoff_write_address;

            b_store_effective_write_data =
                handoff_write_b_data;
        end
    end

    ntt4096_eight_bank_coeff_store_runtime coefficient_store_a ('''
if old_read_assign not in text:
    raise SystemExit("read-data insertion point not found")
text = text.replace(old_read_assign, new_read_assign, 1)

old_a_write = '''        .write_valid     (a_store_write_valid),
        .write_addr      (a_store_write_address),
        .write_data      (a_store_write_data)'''
new_a_write = '''        .write_valid     (a_store_effective_write_valid),
        .write_addr      (a_store_effective_write_address),
        .write_data      (a_store_effective_write_data)'''
if old_a_write not in text:
    raise SystemExit("A-store write connection not found")
text = text.replace(old_a_write, new_a_write, 1)

old_b_write = '''        .write_valid     (b_store_write_valid),
        .write_addr      (b_store_write_address),
        .write_data      (b_store_write_data)'''
new_b_write = '''        .write_valid     (b_store_effective_write_valid),
        .write_addr      (b_store_effective_write_address),
        .write_data      (b_store_effective_write_data)'''
if old_b_write not in text:
    raise SystemExit("B-store write connection not found")
text = text.replace(old_b_write, new_b_write, 1)

old_assert = '''        if (
            busy
            && (
                profile_modulus_we'''
new_assert = '''        if (
            busy
            && (
                handoff_read_valid
                || handoff_write_valid
            )
        )
        begin
            $display(
                "ERROR: idle-only handoff port used while arithmetic busy"
            );

            $fatal(1);
        end

        if (
            busy
            && (
                profile_modulus_we'''
if old_assert not in text:
    raise SystemExit("assertion insertion point not found")
text = text.replace(old_assert, new_assert, 1)

target.write_text(text)
print(f"generated {target}")
