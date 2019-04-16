from os.path import basename
from os.path import join
from glob import glob

configfile: "config.yaml"

index_dir = join(config["workdir"], "index/")
pathogen_index = join(index_dir, "pathogen/")
human_index = join(index_dir, "human/")
sam_dir = join(config["workdir"], "sam_output/")
tmp = join(config["workdir"], "tmp/")
unmapped_dir = join(config["workdir"], "Unmapped/")
basenames = [basename(x).split("_R1")[0] for x in glob(config["sample_dir"] + "*R1.fastq")]
log_dir = join(config["workdir"], "log/")
bam_dir = join(config["workdir"], "bam_output/")
mapped_bam = join(bam_dir, "mapped_bam/")
results = join(config["workdir"], "results/")
accession = join(results, "accession_numbers/")
science_names = join(results, "scientific_names/")
single_names = join(science_names, "single_names/")
bed_dir = join(config["workdir"], "bed/")
bbmap_dir = join(config["workdir"], "bbmap/")
rule all:
    input:
        expand(join(unmapped_dir, "{sample}_{n}.fastq"), sample = basenames, n = [1 ,2])

rule bowtie_index:
    input:
        pathogen_fa = config["pathogen_fasta"],
        human_fa = config["human_fasta"]
    output:
        pathogen_index = directory(pathogen_index),
        human_index = directory(human_index)
    message: "indexing genome & pathogen with bowtie2"
    shell:
        """
        bowtie2-build {input.pathogen_fa} {output.pathogen_index} &
        bowtie2-build {input.human_fa} {output.human_index}  
        """


rule bowtie_to_human:
    input:
        human_index = directory(human_index),
        r1 = join(config["sample_dir"], "{sample}_R1.fastq"),
        r2 = join(config["sample_dir"], "{sample}_R2.fastq")
    params:
        unmapped = join(unmapped_dir, "{sample}_%.fastq")
    output:
        unm_r1 = join(unmapped_dir, "{sample}_1.fastq"),
        unm_r2 = join(unmapped_dir, "{sample}_2.fastq"),
        sam = join(tmp, "{sample}.sam"),
    log: join(log_dir, "{sample}_human_run.log")
    message: "Running Bowtie2 for file {input.r1} against the human genome"
    shell:
        """
        (bowtie2 -x {input.human_index} -1 {input.r1} -2 {input.r2} --un-conc {params.unmapped} -S {output.sam} --no-unal --no-hd --no-sq -p 32) 2> {log}
        """

rule bowtie_to_pathogens:
    input:
        pathogen_index = directory(pathogen_index),
        unm_r1 = join(unmapped_dir, "{sample}_1.fastq"),
        unm_r2 = join(unmapped_dir, "{sample}_2.fastq")
    output:
        sam = join(sam_dir, "{sample}.sam")
    log: join(log_dir, "{sample}_pathogen_run.log")
    message: "Running Bowtie2 for file {input.unm_r1} against the pathogens"
    shell:
        """
        (bowtie2 -x {input.pathogen_index} -1 {input.unm_r1} -2 {input.unm_r2} -S {output.sam} -p 32) 2> {log}
        """

rule sam_to_bam:
    input:
        join(sam_dir, "{sample}.sam")
    output:
        join(bam_dir, "{sample}.bam")
    message: "Converting {input} to {output}"
    shell:
        "samtools view -b -S -o {output} {input}"

rule remove_failed_to_allign:
    input:
        join(bam_dir, "{sample}.bam")
    output:
        join(mapped_bam, "{sample}.bam")
    message: "removing failed to allign for file {input}"
    shell:
        "samtools view -b -F 4 {input} > {output}"

rule bam_to_bed:
    input:
        join(mapped_bam, "{sample}.bam")
    output:
        join(bed_dir, "{sample}.bed")
    log: join(log_dir, "{sample}_bamtobed.log")
    message: "converting mapped bam {input} to bed {output}"
    shell:
        "(bedtools bamtobed -i {input} > {output}) 2> {log}"

rule pileup:
    input:
        join(mapped_bam, "{sample}.bam")
    output:
        join(bbmap_dir, "{sample}_accession.txt")
    message: "genarating accession numbers"
    shell:
        "./scripts/pileup.sh in={input} out={output}"

rule calculate_accession:
    input:
        join(mapped_bam, "{sample}.bam")
    output:
        join(accession, "{sample}.txt")
    message: "calculating accession numbers for {input}"
    shell:
        "samtools view {input} -c -o {output}"