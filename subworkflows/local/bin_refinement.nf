include { DASTOOL_DASTOOL                           } from '../../modules/nf-core/dastool/dastool/main'
include { DASTOOL_FASTATOCONTIG2BIN                 } from '../../modules/nf-core/dastool/fastatocontig2bin/main'
include { GAWK as PROCESS_HMM_TBLOUT                } from '../../modules/nf-core/gawk/main'
include { GAWK as MAGSCOT_PROCESS_CONTIG2BIN        } from '../../modules/nf-core/gawk/main'
include { HMMER_HMMSEARCH as HMMSEARCH_GTDB_PFAM    } from '../../modules/nf-core/hmmer/hmmsearch/main'
include { HMMER_HMMSEARCH as HMMSEARCH_GTDB_TIGRFAM } from '../../modules/nf-core/hmmer/hmmsearch/main'
include { MAGSCOT_CONTIG2BIN2FASTA                  } from '../../modules/local/magscot/contig2bin2fasta/main'
include { MAGSCOT_MAGSCOT                           } from '../../modules/local/magscot/magscot/main'
include { PYRODIGAL                                 } from '../../modules/nf-core/pyrodigal/main'

workflow BIN_REFINEMENT {
    take:
    assemblies
    bins

    main:
    ch_versions     = Channel.empty()
    ch_refined_bins = Channel.empty()

    DASTOOL_FASTATOCONTIG2BIN(bins, 'fa')

    if(params.enable_dastool) {
        ch_contig2bins_to_merge = DASTOOL_FASTATOCONTIG2BIN.out.fastatocontig2bin
            | map {meta, tsv -> [meta.subMap(['id', 'assembler']), tsv] }
            | groupTuple(by: 0)

        ch_dastool_input = assemblies
            | combine(ch_contig2bins_to_merge, by: 0)

        DASTOOL_DASTOOL(ch_dastool_input, [], [])

        ch_versions = ch_versions.mix(
            DASTOOL_FASTATOCONTIG2BIN.out.versions,
            DASTOOL_DASTOOL.out.versions
        )

        ch_dastool_bins = DASTOOL_DASTOOL.out.bins
            | map {meta, fasta -> [ meta + [binner: "DASTool"], fasta ]}

        ch_refined_bins = ch_refined_bins.mix(ch_dastool_bins)
    }

    if(params.enable_magscot) {
        PYRODIGAL(assemblies, 'gff')

        ch_hmmsearch_gtdb_pfam_input = PYRODIGAL.out.faa
            | map { meta, faa ->
                [meta, file(params.hmm_gtdb_pfam), faa, false, true, false]
            }

        ch_hmmsearch_gtdb_tigrfam_input = PYRODIGAL.out.faa
            | map { meta, faa ->
                [meta, file(params.hmm_gtdb_tigrfam), faa, false, true, false]
            }

        HMMSEARCH_GTDB_PFAM(ch_hmmsearch_gtdb_pfam_input)
        HMMSEARCH_GTDB_TIGRFAM(ch_hmmsearch_gtdb_tigrfam_input)

        ch_hmm_output = HMMSEARCH_GTDB_PFAM.out.target_summary
            | mix(HMMSEARCH_GTDB_TIGRFAM.out.target_summary)
            | groupTuple(by: 0)

        PROCESS_HMM_TBLOUT(ch_hmm_output, [])

        MAGSCOT_PROCESS_CONTIG2BIN(
            DASTOOL_FASTATOCONTIG2BIN.out.fastatocontig2bin,
            []
        )

        ch_magscot_contig2bin = MAGSCOT_PROCESS_CONTIG2BIN.out.output
            | map { meta, c2b -> [ meta.subMap(['id', 'assembler']), c2b ] }
            | groupTuple(by: 0)

        ch_magscot_input = PROCESS_HMM_TBLOUT.out.output
            | combine(ch_magscot_contig2bin, by: 0)

        MAGSCOT_MAGSCOT(ch_magscot_input)

        ch_magscot_contig2bin2fasta_input = assemblies
            | combine(MAGSCOT_MAGSCOT.out.contig2bin, by: 0)

        MAGSCOT_CONTIG2BIN2FASTA(ch_magscot_contig2bin2fasta_input)

        ch_magscot_bins = MAGSCOT_CONTIG2BIN2FASTA.out.bins
            | map { meta, rbins -> [ meta + [binner: "magscot"], rbins] }

        ch_refined_bins = ch_refined_bins.mix(ch_magscot_bins)
    }

    emit:
    refined_bins = ch_refined_bins
    versions     = ch_versions
}
