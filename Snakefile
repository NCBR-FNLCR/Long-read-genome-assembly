
###########################################################################
# Long read (PacBio) denovo genome assembly
# Snakemake/5.13.0
###########################################################################
from os.path import join
from snakemake.io import expand, glob_wildcards

configfile: "/data/NCBR/projects/DenovoLRA_NR/test1/config.yaml"

result_dir = config["result_dir"]
Genome = config["genome_size"]
Coverage = config["coverage"]
Lineage = config["lineage"]
Lineage_name = config["lineage_name"]

SAMPLE, = glob_wildcards(join(result_dir, "raw/{samples}.bam"))
ASSEMBLER = ["canu", "flye", "raven", "wtdbg2", "minipolish"]

rule All:
    input:
        # Converting BAM to Fastq to Fasta
        expand(join(result_dir,"reads/{samples}.fastq"), samples=SAMPLE),
        expand(join(result_dir,"reads/{samples}.fasta"), samples=SAMPLE),

        # Canu assembly
        expand(join(result_dir, "canu_assembly/{samples}.contigs.fasta"), samples=SAMPLE),

        # Flye assembly
        expand(join(result_dir,"flye_assembly/{samples}.assembly.fasta"), samples=SAMPLE),

        # Raven assembly
        #expand(join(result_dir,"raven_assembly/{samples}.raven-graph.gfa"), samples=SAMPLE),
        expand(join(result_dir,"raven_assembly/{samples}.raven-graph.fasta"), samples=SAMPLE),

        # Wtdbg2 assembly
        expand(join(result_dir,"wtdbg2_assembly/{samples}.wtdbg2.ctg.lay.gz"), samples=SAMPLE),
        expand(join(result_dir,"wtdbg2_assembly/{samples}.wtdbg2.ctg.fa"), samples=SAMPLE),

        # Minipolish (minimap2-miniasm-racon) assembly
        expand(join(result_dir,"minipolish_assembly/{samples}.minipolished-assembly.fa"), samples=SAMPLE),

        # Gather assemblies in a directory
        expand(join(result_dir,"all-assemblies/{samples}.{assemblers}.fasta"), samples=SAMPLE, assemblers=ASSEMBLER),
        expand(join(result_dir,"all-assemblies/{samples}.canu.fasta"), samples=SAMPLE),
        expand(join(result_dir,"all-assemblies/{samples}.flye.fasta"), samples=SAMPLE),
        expand(join(result_dir,"all-assemblies/{samples}.minipolish.fasta"), samples=SAMPLE),
        expand(join(result_dir,"all-assemblies/{samples}.raven.fasta"), samples=SAMPLE),
        expand(join(result_dir,"all-assemblies/{samples}.wtdbg2.fasta"), samples=SAMPLE),
        
        # Quast - assembly statistics without reference
        join(result_dir,"sample-quast/report.html"),
        expand(join(result_dir,"stats_busco/{assemblers}/short_summary.specific.{Lineage_name}.{assemblers}.txt"), assemblers=ASSEMBLER, Lineage_name=Lineage_name),
        join(result_dir,"busco-summaries/busco_figure.png"),

        # Scaffolders (ScaRa)
        expand(join(result_dir, "minimap2_overlaps/{samples}.read-read-overlap.paf"),samples=SAMPLE),
        expand(join(result_dir, "minimap2_overlaps/{samples}.{assemblers}-contig-overlap.paf"),samples=SAMPLE, assemblers=ASSEMBLER),
        expand(join(result_dir, "minimap2_overlaps/{samples}.canu-contig-overlap.paf"),samples=SAMPLE),
        expand(join(result_dir, "minimap2_overlaps/{samples}.raven-contig-overlap.paf"),samples=SAMPLE),
        expand(join(result_dir, "minimap2_overlaps/{samples}.minipolish-contig-overlap.paf"),samples=SAMPLE),
        expand(join(result_dir, "minimap2_overlaps/{samples}.flye-contig-overlap.paf"),samples=SAMPLE),
        expand(join(result_dir, "minimap2_overlaps/{samples}.wtdbg2-contig-overlap.paf"),samples=SAMPLE),

    output:
        "multiqc_report.html"
    params:
        rname="denovoAsm"
    shell:
        """
        module load multiqc/1.8
        multiqc .
        """

rule BAM_to_Fasta:
    input:
        join(result_dir, "raw/{samples}.bam")
    output:
        FQ=join(result_dir, "reads/{samples}.fastq"),
        FA=join(result_dir, "reads/{samples}.fasta")
    params:
        rname="BAM_to_Fasta",
        samtools="samtools/1.9",
        seqkit="seqkit/0.12.1",
        dir=directory(join(result_dir, "reads"))
    shell:
        """
        module load {params.samtools}
        module load {params.seqkit}
        mkdir -p {params.dir}
        samtools fastq {input} > {output.FQ}
        seqkit fq2fa --line-width 0 {output.FQ} -o {output.FA}
        """

rule raven_assembly:
    input:
        join(result_dir,"reads/{samples}.fasta")
    output:
        gfa=join(result_dir, "raven_assembly/{samples}.raven-graph.gfa"),
        fa=join(result_dir, "raven_assembly/{samples}.raven-graph.fasta")
    params:
        rname="raven_assembly",
        dir=directory(join(result_dir, "raven_assembly")),
        gfa="{samples}.raven-graph.gfa",
    #conda: "envs/raven-assembler.yaml"
    threads: 32
    shell:
        """
        source /data/NCBR/apps/genome-assembly/conda/etc/profile.d/conda.sh
        conda activate raven-assembler
        mkdir -p {params.dir}
        cd {params.dir}
        #raven --threads {threads} {input} > {output.fa}
        raven --graphical-fragment-assembly {params.gfa} --threads {threads} {input}
        awk '$1 ~/S/ {{print ">"$2"\\n"$3}}' {output.gfa} > {output.fa}
        conda deactivate
        """

rule wtdbg2_assembly:
    input:
        join(result_dir,"reads/{samples}.fasta")
    output:
        lay=join(result_dir,"wtdbg2_assembly/{samples}.wtdbg2.ctg.lay.gz"),
        fa=join(result_dir,"wtdbg2_assembly/{samples}.wtdbg2.ctg.fa")
    params:
        rname="wtdbg2_assembly",
        dir=directory(join(result_dir,"wtdbg2_assembly")),
        tag="{samples}.wtdbg2"
    threads: 32
    #conda: "envs/wtdbg2.yaml"
    shell:
        """
        source /data/NCBR/apps/genome-assembly/conda/etc/profile.d/conda.sh
        conda activate wtdbg2
        mkdir -p {params.dir}
        cd {params.dir}
        wtdbg2 -x sq -g {Genome} -t {threads} -i {input} -f -o {params.tag}
        wtpoa-cns -t {threads} -i {output.lay} -fo {output.fa}
        conda deactivate
        """

rule minipolish_assembly:
    input:
        join(result_dir,"reads/{samples}.fastq")
    output:
        ovlp=join(result_dir,"minipolish_assembly/{samples}.minimap2-overlaps.paf"),
        gfa1=join(result_dir,"minipolish_assembly/{samples}.miniasm-assembly.gfa"),
        gfa2=join(result_dir,"minipolish_assembly/{samples}.minipolished-assembly.gfa"),
        fa=join(result_dir,"minipolish_assembly/{samples}.minipolished-assembly.fa")
    params:
        rname="minipolish_assembly",
        dir=directory(join(result_dir,"minipolish_assembly"))
    #conda: "envs/minipolish.yaml"
    threads: 32
    shell:
        """
        source /data/NCBR/apps/genome-assembly/conda/etc/profile.d/conda.sh
        conda activate minipolish
        mkdir -p {params.dir}
        module load miniasm/0.3.r179
        minimap2 -t {threads} -x ava-pb {input} {input} > {output.ovlp}
        miniasm -f {input} {output.ovlp} > {output.gfa1}
        minipolish --threads {threads} {input} {output.gfa1} > {output.gfa2}
        awk '$1 ~/S/ {{print ">"$2"\\n"$3}}' {output.gfa2} > {output.fa}
        conda deactivate
        """

rule flye_assembly:
    input:
        join(result_dir,"reads/{samples}.fastq")
    output:
        join(result_dir,"flye_assembly/{samples}.assembly.fasta")
    params:
        rname="flye_assembly",
        dir=directory(join(result_dir,"flye_assembly")),
        flye="flye/2.7"
    threads: 100
    shell:
        """
        module load {params.flye}
        cd /lscratch/$SLURM_JOBID
        flye --threads {threads} --pacbio-raw {input} --genome-size {Genome} --out-dir {params.dir} --asm-coverage {Coverage}
        mv /lscratch/$SLURM_JOBID/{params.rname} {result_dir}
        cd {params.dir}
        cp assembly.fasta {output}
        """

rule canu_assembly:
    input:
        join(result_dir,"reads/{samples}.fastq")
    output:
        FA=join(result_dir,"canu_assembly/{samples}.contigs.fasta")
    params:
        rname="canu_assembly",
        dir=directory(join(result_dir,"canu_assembly")),
        tag="{samples}",
        canu="canu/2.0"
    threads: 32
    shell:
        """
        module load {params.canu}
        mkdir -p {params.dir}
        canu -p {params.tag} -d {params.dir} -fast genomeSize={Genome} minThreads={threads} maxThreads={threads} maxMemory=100 stopOnLowCoverage=0 useGrid=false -pacbio-raw {input}
        """

rule gather_assemblies:
    input:
        A1=expand(join(result_dir,"canu_assembly/{samples}.contigs.fasta"), samples=SAMPLE),
        A2=expand(join(result_dir,"flye_assembly/{samples}.assembly.fasta"), samples=SAMPLE),
        A3=expand(join(result_dir,"minipolish_assembly/{samples}.minipolished-assembly.fa"), samples=SAMPLE),
        A4=expand(join(result_dir,"raven_assembly/{samples}.raven-graph.fasta"), samples=SAMPLE),
        A5=expand(join(result_dir,"wtdbg2_assembly/{samples}.wtdbg2.ctg.fa"), samples=SAMPLE)
    output:
        A1=expand(join(result_dir,"all-assemblies/{samples}.canu.fasta"), samples=SAMPLE),
        A2=expand(join(result_dir,"all-assemblies/{samples}.flye.fasta"), samples=SAMPLE),
        A3=expand(join(result_dir,"all-assemblies/{samples}.minipolish.fasta"), samples=SAMPLE),
        A4=expand(join(result_dir,"all-assemblies/{samples}.raven.fasta"), samples=SAMPLE),
        A5=expand(join(result_dir,"all-assemblies/{samples}.wtdbg2.fasta"), samples=SAMPLE),
    params:
        rname = "gather_assemblies",
        dir=join(result_dir, "all-assemblies")
    shell:
        """
        mkdir -p {params.dir}
        cp {input.A1} {output.A1}
        cp {input.A2} {output.A2}
        cp {input.A3} {output.A3}
        cp {input.A4} {output.A4}
        cp {input.A5} {output.A5}
        """

rule minimap2_overlaps:
    input:
        #A=join(result_dir,"all-assemblies/{samples}.{assemblers}.fasta"), 
        A1=expand(join(result_dir, "all-assemblies/{samples}.canu.fasta"),samples=SAMPLE),
        A2=expand(join(result_dir, "all-assemblies/{samples}.raven.fasta"),samples=SAMPLE),
        A3=expand(join(result_dir, "all-assemblies/{samples}.minipolish.fasta"),samples=SAMPLE),
        A4=expand(join(result_dir, "all-assemblies/{samples}.flye.fasta"),samples=SAMPLE),
        A5=expand(join(result_dir, "all-assemblies/{samples}.wtdbg2.fasta"),samples=SAMPLE),
    output:
        #A=join(result_dir,"all-assemblies/{samples}.{assemblers}-contig-overlap.paf"), 
        ovlp=expand(join(result_dir,"minimap2_overlaps/{samples}.read-read-overlap.paf"),samples=SAMPLE),
        A1=expand(join(result_dir, "minimap2_overlaps/{samples}.canu-contig-overlap.paf"),samples=SAMPLE),
        A2=expand(join(result_dir, "minimap2_overlaps/{samples}.raven-contig-overlap.paf"),samples=SAMPLE),
        A3=expand(join(result_dir, "minimap2_overlaps/{samples}.minipolish-contig-overlap.paf"),samples=SAMPLE),
        A4=expand(join(result_dir, "minimap2_overlaps/{samples}.flye-contig-overlap.paf"),samples=SAMPLE),
        A5=expand(join(result_dir, "minimap2_overlaps/{samples}.wtdbg2-contig-overlap.paf"),samples=SAMPLE),        
    params:
        rname="minimap2_overlaps",
        raw=expand(join(result_dir, "reads/{samples}.fasta"),samples=SAMPLE),
        ovlp=expand(join(result_dir,"minimap2_overlaps/{samples}.read-read-overlap.paf"),samples=SAMPLE),
        dir=directory(join(result_dir,"minimap2_overlaps"))
    threads: 32
    shell:
        """
        module load minimap2/2.17
        mkdir -p {params.dir}
        minimap2 -t {threads} -x ava-pb {params.raw} {params.raw} > {params.ovlp}
        minimap2 -t {threads} -x ava-pb {params.raw} {input.A1} > {output.A1}
        minimap2 -t {threads} -x ava-pb {params.raw} {input.A2} > {output.A2}
        minimap2 -t {threads} -x ava-pb {params.raw} {input.A3} > {output.A3}
        minimap2 -t {threads} -x ava-pb {params.raw} {input.A4} > {output.A4}
        minimap2 -t {threads} -x ava-pb {params.raw} {input.A5} > {output.A5}
        """

rule stats_quast:
    input:
        asm=expand(join(result_dir,"all-assemblies/{samples}.{assemblers}.fasta"), samples=SAMPLE, assemblers=ASSEMBLER),
    output:
        ST=join(result_dir,"sample-quast/report.html"),
    params:
        rname="stats_quast",
        batch='--cpus-per-task=72 --mem=100g --time=10:00:00',
        dir=directory("sample-quast")
    threads: 32
    shell:
        """
module unload python
module load quast/5.0.2
module load circos/0.69-9
quast.py -o {params.dir} -t {threads} --circos -L {input.asm}
        """

rule stats_busco:
    input:
        asm=join(result_dir, "all-assemblies/NF54_NIH-4.{assemblers}.fasta"),
    output:
        ST=join(result_dir,"stats_busco/{assemblers}/short_summary.specific.{Lineage_name}.{assemblers}.txt"),
    params:
        rname="stats_busco",
        dir=directory(join(result_dir, "stats_busco")), 
        folder="{assemblers}",
    threads: 32
    shell:
        """
        module load busco/4.0.2
        mkdir -p {params.dir}
        mkdir -p {params.dir}/{params.folder}
        cd {params.dir}
        busco --offline -m genome -l {Lineage} -c {threads} -i {input.asm} -f -o {params.folder}
        """


rule busco_summaries:
    input:
        expand(join(result_dir,"stats_busco/{assemblers}/short_summary.specific.{Lineage_name}.{assemblers}.txt"), assemblers=ASSEMBLER, Lineage_name=Lineage_name),
    output:
        join(result_dir,"busco-summaries/busco_figure.png"),
    params:
        rname="busco_summaries",
        dir=directory(join(result_dir, "busco-summaries")),
    shell:
        """
module load busco/4.0.2
mkdir -p {params.dir}
cp {input} {params.dir}
python3 /usr/local/apps/busco/4.0.2/generate_plot.py -rt specific –wd {params.dir}
        """

