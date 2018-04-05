import "QC/QC.wdl" as qc
import "tasks/biopet.wdl" as biopet


workflow readgroup {
    Array[File] sampleConfigs
    String readgroupId
    String libraryId
    String sampleId
    String? platform = "illumina"
    String outputDir

    call biopet.SampleConfig as config {
        input:
             inputFiles = sampleConfigs,
             sample = sampleId,
             library = libraryId,
             readgroup = readgroupId,
             tsvOutputPath = outputDir + "/" + readgroupId + ".config.tsv"
    }

    # make the readgroup line for STAR
    call makeStarRGline as rgLine {
        input:
            sample = sampleId,
            library = libraryId,
            platform = platform,
            readgroup = readgroupId
    }

    call qc.QC as qc_call {
        input:
            read1 = config.values.R1,
            read2 = config.values.R2,
            outputDir = outputDir + "QC/"
    }

    output {
        File cleanR1 = qc_call.read1afterQC
        File? cleanR2 = qc_call.read2afterQC
        String? starRGline = rgLine.rgLine
    }
}


task makeStarRGline {
    String sample
    String library
    String platform
    String readgroup

    command {
        echo '"ID:${readgroup}" "LB:${library}" "PU:${platform}" "SM:${sample}"'
    }

    output {
        String? rgLine = stdout()
    }
}
