import "bam-to-gvcf/gvcf.wdl" as gvcf
import "library.wdl" as libraryWorkflow
import "tasks/biopet.wdl" as biopet
import "tasks/common.wdl" as common
import "tasks/samtools.wdl" as samtools

workflow sample {
    Array[File] sampleConfigs
    String sampleId
    String sampleDir
    File refFasta
    File refDict
    File refFastaIndex

    call biopet.SampleConfig as config {
        input:
            inputFiles = sampleConfigs,
            sample = sampleId,
            tsvOutputPath = sampleDir + "/" + sampleId + ".config.tsv",
            keyFilePath = sampleDir + "/" + sampleId + ".config.keys"
    }

    scatter (lib in read_lines(config.keysFile)) {
        if (lib != "") {
            call libraryWorkflow.library as library {
                input:
                    outputDir = sampleDir + "/lib_" + lib + "/",
                    sampleConfigs = sampleConfigs,
                    sampleId = sampleId,
                    libraryId = lib,
                    refFasta = refFasta,
                    refDict = refDict,
                    refFastaIndex = refFastaIndex
            }

            # Necessary for predicting the path to the BAM/BAI in linkBam and linkIndex
            String libraryId = lib
        }
    }

    Boolean multipleBams = length(library.bamFile) > 1

    # Merge library (mdup) bams into one (for counting).
    if (multipleBams) {
        call samtools.Merge as mergeLibraries {
            input:
                bamFiles = select_all(library.bamFile),
                outputBamPath = sampleDir + "/" + sampleId + ".bam"
        }

        call samtools.Index as mergedIndex {
            input:
                bamFilePath = mergeLibraries.outputBam,
                bamIndexPath = sampleDir + "/" + sampleId + ".bai"
        }
    }

    # Create links instead, if ther is only one bam, to retain output structure.
    if (! multipleBams) {
        String lib = select_first(libraryId)
        call common.createLink as linkBam {
            input:
                inputFile = sampleDir + "/lib_" + lib + "/" + sampleId + "-" + lib + ".markdup.bam",
                outputPath = sampleDir + "/" + sampleId + ".bam"
        }

        call common.createLink as linkIndex {
            input:
                inputFile = sampleDir + "/lib_" + lib + "/" + sampleId + "-" + lib + ".markdup.bai",
                outputPath = sampleDir + "/" + sampleId + ".bai"
        }
    }

    # variant calling, requires different bam file than counting
    call gvcf.Gvcf as createGvcf {
        input:
            refFasta = refFasta,
            refDict = refDict,
            refFastaIndex = refFastaIndex,
            bamFiles = select_all(library.preprocessBamFile),
            bamIndexes = select_all(library.preprocessBamIndexFile),
            gvcfPath = sampleDir + "/" + sampleId + ".g.vcf.gz"
    }

    output {
        String sampleName = sampleId
        File bam = if multipleBams then select_first([mergeLibraries.outputBam]) else select_first(library.bamFile)
        File bai = if multipleBams then select_first([mergedIndex.indexFile]) else select_first(library.bamIndexFile)
        File gvcfFile = createGvcf.outputGVCF
        File gvcfFileIndex = createGvcf.outputGVCFindex
    }
}
