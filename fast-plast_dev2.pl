#!/usr/bin/env perl -w
use strict;
use Getopt::Long;
use Pod::Usage;
use FindBin;
use lib ("$FindBin::Bin/PerlLib");
use File::Spec;
#use File::Which;
#use File::Which qw(which where);
use Cwd;
use Cwd 'abs_path';

BEGIN {

    $ENV{FP_HOME} = "$FindBin::Bin";

}


###directories
my $FPROOT = "$FindBin::RealBin";
my $AFIN_DIR = "/mnt/research/edgerpat_lab/Strawberry_GSS/bin/Fast-Plast/afin/";
my $COVERAGE_DIR = "$FPROOT/Coverage_Analysis";
my $FPBIN = "$FPROOT/bin";
my $TRIMMOMATIC="/mnt/ls15/scratch/users/mrmckain/Test_Fast-Plast/Fast-Plast-master/bin/Trimmomatic-0.36/trimmomatic-0.36.jar";
my $BOWTIE2="/mnt/ls15/scratch/users/mrmckain/Test_Fast-Plast/Fast-Plast-master/bin/bowtie2-2.2.9/bowtie2";
my $SPADES="/mnt/ls15/scratch/users/mrmckain/Test_Fast-Plast/Fast-Plast-master/bin/SPAdes-3.9.0-Linux/bin/spades.py";
my $BLAST="/mnt/ls15/scratch/users/mrmckain/Test_Fast-Plast/Fast-Plast-master/bin/ncbi-blast-2.6.0+/bin/";
my $SSPACE="/mnt/ls15/scratch/users/mrmckain/Test_Fast-Plast/Fast-Plast-master/bin/sspace_basic-2.1.1/SSPACE_Basic.pl";
my $BOWTIE1="/mnt/ls15/scratch/users/mrmckain/Test_Fast-Plast/Fast-Plast-master/bin/bowtie-1.1.2/bowtie";
my $JELLYFISH="/mnt/ls15/scratch/users/mrmckain/Test_Fast-Plast/Fast-Plast-master/bin/jellyfish-2.2.6/bin/jellyfish";


my $help;
my $paired_end1;
my $paired_end2;
my $single_end;
my $name;
my $bowtie_index=$FPBIN . "/Verdant";
my $posgenes= $FPBIN . "/Angiosperm_Chloroplast_Genes.fsa";
my $coverage_check;
my $min_coverage = 0;
my $threads = 4;
my $adapters = $FPBIN . "/NEB-PE.fa";

GetOptions('help|?' => \$help, "1=s" => \$paired_end1, "2=s" => \$paired_end2, "single=s" => \$single_end, "bowtie_index=s" => \$bowtie_index, "name=s" => \$name, 'coverage_analysis' => \$coverage_check,'positional_genes' => \$posgenes, "threads=i" => \$threads, "min_coverage=i" => \$min_coverage, "adapters=s" => \$adapters)  or pod2usage( { -message => "ERROR: Invalid parameter." } );


if ($help) {
    pod2usage( { -exitstatus => 0 } );
}

if ( !$paired_end1 && !$single_end ) {
    pod2usage( { -message => "ERROR: Missing reads file(s)." } );
}

if (!$paired_end1 && $paired_end2 || !$paired_end2 && $paired_end1){
	pod2usage( { -message => "ERROR: Missing other paired end file." } );
}

if ( !$name ) {
    pod2usage( { -message => "ERROR: Missing sample name." } );
}

### Get full paths for files.  Glob would work for all of them, but it requires perl 5.6+.  Only using it for the ~ calls, just in case. ####
my $datestring = localtime();
my $start_time = time;
open(STDERR, '>', $name.'_results_error.log') or die "Can't open log";

print "$datestring\tStarting Fast-Plast.\n";

my @p1_array;
if($paired_end1){
	my @temp_array = split(",", $paired_end1);
	for my $tfile (@temp_array){
		if($tfile =~ /~/){
			$tfile = glob ($tfile);
		}
		my $abs_path = abs_path($tfile);
		push(@p1_array, $abs_path);
	}
}
my @p2_array;
if($paired_end2){ 
	my @temp_array = split(",", $paired_end2);
	for my $tfile (@temp_array){
		if($tfile =~ /~/){
			$tfile = glob ($tfile);
		}
		my $abs_path = abs_path($tfile);
		push(@p2_array, $abs_path);
	}
}
my @s_array; 
if($single_end){
	my @temp_array = split(",", $single_end);
	for my $tfile (@temp_array){
		if($tfile =~ /~/){
			$tfile = glob ($tfile);
		}
		my $abs_path = abs_path($tfile);
		push(@s_array, $abs_path);
	}
}

my $pe_libs = @p1_array;
my $s_libs = @s_array;

if(!$pe_libs){
	$pe_libs = 0;
}
if(!$s_libs){
	$s_libs = 0;
}

print "Assemblying plastome with $s_libs single end libraries and $pe_libs paired end libraries.\n";


###Get read size###
my $current_runtime = localtime(); 
print "$current_runtime\tDetermining best kmer sizes.\n";

my $maxsize=0;

if(@p1_array){
	for my $file (@p1_array){
		open my $tfile, "<", $file;
		my $count = 0;
		SIZE: while(<$tfile>){
				my $seq = readline($tfile);
				chomp($seq);
				if(length($seq) > $maxsize){
						$maxsize = length($seq);
				}
				$count++;
				if($count == 100){
					last SIZE;
				}
				readline($tfile);
				readline($tfile);
			}
	}
}


if(@p2_array){
	for my $file (@p2_array){
		open my $tfile, "<", $file;
		my $count = 0;
		SIZE: while(<$tfile>){
				my $seq = readline($tfile);
				chomp($seq);
				if(length($seq) > $maxsize){
						$maxsize = length($seq);
				}
				$count++;
				if($count == 100){
					last SIZE;
				}
				readline($tfile);
				readline($tfile);
			}
	}
}

if(@s_array){
	for my $file (@s_array){
		open my $tfile, "<", $file;
		my $count = 0;
		SIZE: while(<$tfile>){
				my $seq = readline($tfile);
				chomp($seq);
				if(length($seq) > $maxsize){
						$maxsize = length($seq);
				}
				$count++;
				if($count == 100){
					last SIZE;
				}
				readline($tfile);
				readline($tfile);
			}
	}
}
##########

###Set K-mer Size###
my $spades_kmer;
if($maxsize >= 140){
	$spades_kmer = "55,87,121";
}
elsif($maxsize >= 100){
	$spades_kmer = "55,69,87";
}
elsif($maxsize >= 80){
	$spades_kmer = "45,57,69";
}
elsif($maxsize >= 50){
	$spades_kmer = "31,37,43";
}
else{
	$spades_kmer = "23,27,31";
}

print "K-mer sizes for SPAdes set at $spades_kmer.\n";
##########

########## Create Directory ###########

mkdir("$name");
chdir("$name");
########## Start Trimmomatic ##########
$current_runtime = localtime();
print "$current_runtime\tStarting read trimming with Trimmomatic.\nUsing $TRIMMOMATIC.\n";

mkdir("Trimmed_Reads");
chdir("Trimmed_Reads");
if(@p1_array){
	for (my $i=0; $i < $pe_libs; $i++){
		my $trim_exec = "java -classpath " . $TRIMMOMATIC . " org.usadellab.trimmomatic.TrimmomaticPE -threads " . $threads . " " . $p1_array[$i] . " " . $p2_array[$i] . " " . $name."_".$i.".trimmed_P1.fq " . $name."_".$i.".trimmed_U1.fq " . $name."_".$i.".trimmed_P2.fq " . $name."_".$i.".trimmed_U2.fq " . "ILLUMINACLIP:".$adapters.":1:30:10 SLIDINGWINDOW:10:20 MINLEN:40";
		system($trim_exec);
	}
	`cat $name\*trimmed_P1.fq > $name.trimmed_P1.fq`;
	`cat $name\*trimmed_P2.fq > $name.trimmed_P2.fq`;
	`cat $name\*trimmed_U*.fq > $name.trimmed_UP.fq`;
}

if(@s_array){
	for (my $i=0; $i < $s_libs; $i++){
		my $trim_exec = "java -classpath " . $TRIMMOMATIC . " org.usadellab.trimmomatic.TrimmomaticSE -threads " . $threads . " " . $s_array[$i] . " " . $name."_".$i.".trimmed_SE.fq " . "ILLUMINACLIP:".$adapters.":1:30:10 SLIDINGWINDOW:10:20 MINLEN:40";
		system($trim_exec);
	}
	`cat $name\*trimmed_SE.fq >> $name.trimmed_UP.fq`;
}
chdir("../");

########## Start Bowtie2 ##########

$current_runtime = localtime();
print "$current_runtime\tStarting read mapping with bowtie2.\nUsing $BOWTIE2.\n";


mkdir("Bowtie_Mapping");
chdir("Bowtie_Mapping");
my $bowtie2_exec = $BOWTIE2 . " --very-sensitive-local --al map_hits.fq --al-conc map_pair_hits.fq -p " . $threads . " -x " . $bowtie_index . " -1 ../Trimmed_Reads/" . $name . ".trimmed_P1.fq -2 ../Trimmed_Reads/" . $name . ".trimmed_P2.fq -U ../Trimmed_Reads/" . $name . ".trimmed_UP.fq -S " . $name . ".sam";
#system($bowtie2_exec);
chdir("../");

########## Start SPAdes ##########

$current_runtime = localtime();
print "$current_runtime\tStarting initial assembly with SPAdes.\nUsing $SPADES.\n";
mkdir("Spades_Assembly");
chdir("Spades_Assembly");

my $spades_exec = "python " . $SPADES . " -o spades_iter1 -1 ../Bowtie_Mapping/map_pair_hits.1.fq -2 ../Bowtie_Mapping/map_pair_hits.2.fq -s ../Bowtie_Mapping/map_hits.fq --only-assembler -k " . $spades_kmer . " -t " . $threads;
#system($spades_exec);
chdir("../");
########## Start Afin ##########
$current_runtime = localtime();
print "$current_runtime\tStarting improved assembly with afin.\n";

mkdir("Afin_Assembly");
chdir("Afin_Assembly");

`perl $FPBIN/filter_spades_contigs_weigthed.pl ../Spades_Assembly/spades_iter1/contigs.fasta`;

my %temp_filtered;
my $temp_filter_id;
open my $file_filter, "<", "filtered_spades_contigs.fsa";
open my $out_filter, ">", "temp_filtered_spades_contigs.fsa";
while(<$file_filter>){
	chomp;
	if(/>/){
		$temp_filter_id=$_;
	}
	else{
		$temp_filtered{$temp_filter_id}.=$_;
	}
}
my @bases = ("A", "C", "T", "G");

my %repeats;
for my $base (@bases){
	for my $base2 (@bases){
		$repeats{$base.$base2}=0;
		$repeats{$base2.$base}=0;
	}
}

for my $temp_seq (keys %temp_filtered){
	my %temprepeats=%repeats;
	for my $re (keys %repeats){
	
		for (my $i =0; $i <= length($temp_filtered{$temp_seq})-1; $i++){
			my $result = index($temp_filtered{$temp_seq}, $re, $i);
			if($result >= 0){
				$temprepeats{$re}++;
				$i = $result;
			}	
		}
		
	}
	   my $max_repeat=0;
                for my $re_val (keys %temprepeats){
                        if($temprepeats{$re_val} >$max_repeat){
                                $max_repeat = $temprepeats{$re_val};
                        }
                }
	if($max_repeat/(length($temp_filtered{$temp_seq})/2) > 0.5){
		next;
	}
	else{
		print $out_filter "$temp_seq\n$temp_filtered{$temp_seq}\n";
	}
}
`mv temp_filtered_spades_contigs.fsa filtered_spades_contigs.fsa`;


my $current_afin;
my $extension = $maxsize*0.75;
my ($total_afin_contigs, $max_afin, $min_afin) = 1;#&run_afin(200,100,"20,15,10","2,1,1","filtered_spades_contigs.fsa",$extension);
print "After afin, there are $total_afin_contigs contigs with a maximum size of $max_afin and a minimum size of $min_afin.\n";
$total_afin_contigs=2;
$current_runtime = localtime();
print "$current_runtime\tRemoving nested contigs.\n";
my $gotofinish;
if( $total_afin_contigs > 1){
	$current_afin = $name . "_afin_iter0.fa";

	`$BLAST/makeblastdb -in $current_afin -dbtype nucl`;
	my $blast_afin_exec = $BLAST . "blastn -query " . $current_afin . " -db " . $current_afin . " -evalue 1e-40 -outfmt 6 -max_target_seqs 1000000 > " . $current_afin . ".blastn";
	`$blast_afin_exec`;

	remove_nested($current_afin, $current_afin.".blastn");
	
	$total_afin_contigs = &count_contigs($current_afin);

	if ($total_afin_contigs > 1){
		my ($percent_recovered_genes, $contigs_db_genes) = &cpgene_recovery($current_afin);
		my %contigs_db_genes = %$contigs_db_genes;
		$percent_recovered_genes=$percent_recovered_genes*100;
		print "$percent_recovered_genes\% of known angiosperm chloroplast genes were recovered in retained contigs.\n";


		$current_afin = &scaffolding($current_afin,$name);
		rename($current_afin, $name.".final.scaffolds.fasta");
		$current_afin=$name.".final.scaffolds.fasta";
		$total_afin_contigs = &count_contigs($current_afin);
		if($total_afin_contigs > 1){
				my $temppwd = `pwd`;
				chomp($temppwd);
				$temppwd .= "/". $current_afin;
				open my $cpcomposition, ">", "Chloroplast_gene_composition_of_final_contigs.txt";
			for my $contig_name (sort keys %contigs_db_genes){
				for my $gene_name (sort keys %{$contigs_db_genes{$contig_name}}){
						print $cpcomposition "$contig_name\t$gene_name\n";
				}
			}
			close ($cpcomposition);
				die "Cannot scaffold contigs into a single piece.  Coverage is too low. Best contigs are in $temppwd\. A list of genes in each contig can be found in \"Chloroplast_gene_composition_of_final_contigs.txt\"\.\n";
		}
	}	

	else{

		my ($percent_recovered_genes, $contigs_db_genes) = &cpgene_recovery($current_afin);
		my %contigs_db_genes = %$contigs_db_genes;
		$percent_recovered_genes=$percent_recovered_genes*100;
		print "$percent_recovered_genes\% of known angiosperm chloroplast genes were recovered in retained contigs.\n";
		open my $cpcomposition, ">", "Chloroplast_gene_composition_of_final_contigs.txt";
			for my $contig_name (sort keys %contigs_db_genes){
				for my $gene_name (sort keys %{$contigs_db_genes{$contig_name}}){
						print $cpcomposition "$contig_name\t$gene_name\n";
				}
			}
		close ($cpcomposition);
	
	}	




}
    


else{
	$current_afin = $name . "_afin_iter0.fa";
	
	my ($percent_recovered_genes, $contigs_db_genes) = &cpgene_recovery($current_afin);
	my %contigs_db_genes = %$contigs_db_genes;
	$percent_recovered_genes=$percent_recovered_genes*100;
	print "$percent_recovered_genes\% of known angiosperm chloroplast genes were recovered in retained contigs.\n";
	open my $cpcomposition, ">", "Chloroplast_gene_composition_of_final_contigs.txt";
			for my $contig_name (sort keys %contigs_db_genes){
				for my $gene_name (sort keys %{$contigs_db_genes{$contig_name}}){
						print $cpcomposition "$contig_name\t$gene_name\n";
				}
			}
	close ($cpcomposition);
}

chdir("../");

########## Start Plastome Finishing ##########

$current_runtime = localtime(); 
print "$current_runtime\tStarting plastome finishing.\nUsing $posgenes for LSC, SSC, and IR identification.\n";

mkdir("Plastome_Finishing");
chdir("Plastome_Finishing");

orientate_plastome("../Afin_Assembly/".$current_afin, $name); 
chdir("../");
$current_runtime = localtime();
print "$current_runtime\tAssembly finished.\n";

########## Start Coverage Analysis ##########
if($coverage_check){
$current_runtime = time - $start_time;
print "$current_runtime\tStarting coverage analyses.\n";
my $check_finish = "Plastome_Finishing/".$name."_FULLCP.fsa";
unless(-e $check_finish){
	die "Cannot complete coverage analysis. Full chloroplast genome not complete.";
}
mkdir("Coverage_Analysis");
chdir("Coverage_Analysis");
my $build_bowtie2_exec = $BOWTIE2 . "-build ../Plastome_Finishing/" . $name . "_FULLCP.fsa" . $name . "_bowtie";
system($build_bowtie2_exec);

my $cov_bowtie2_exec = $BOWTIE2 . " --very-sensitive-local --quiet --al map_hits.fq --al-conc map_pair_hits.fq -p " . $threads . " -x " . $name ."_bowtie" . " -1 ../Trimmed_Reads/" . $name . ".trimmed_P1.fq -2 ../Trimmed_Reads/" . $name . ".trimmed_P2.fq -U ../Trimmed_Reads/" . $name . ".trimmed_UP.fq -S " . $name . ".sam";
system($cov_bowtie2_exec);

my $jellyfish_count_exec = $JELLYFISH . "count -m 25 -t ". $threads . " -C -s 1G map_*";
system($jellyfish_count_exec);

my $jellyfish_dump_exec = $JELLYFISH . "dump mer_counts.jf . > " . $name . "_25dump";
system($jellyfish_dump_exec);

my $window_cov_exec = "perl " . $COVERAGE_DIR . "/new_window_coverage.pl " . $name . "_25dump ../Plastome_Finishing/" . $name . "_FULLCP.fsa " . $name . " 25";
system($window_cov_exec);

my $rscript_exec = "Rscript " . $COVERAGE_DIR . "/plot_coverage.r " . $name . ".coverage_25kmer.txt ". $name;
system($rscript_exec);

my $check_cov_exec = "perl " . $COVERAGE_DIR . "/check_plastid_coverage.pl " . $name . ".coverage_25kmer.txt 25 " . $min_coverage;
system($check_cov_exec);

chdir("../");
$current_runtime = localtime(); 
print "$current_runtime\tCoverage analysis finished.\n";
}
else{
	print "Coverage analysis was not selected.  We highly recommend this option to verify the assembly.\n";
}


	
##########
sub scaffolding {
	$current_runtime = localtime();
	print "$current_runtime\tStarting scaffolding with SSPACE.\n";
	mkdir ("Scaffolding");
	chdir("Scaffolding");
	my @p1_temp = <../../Trimmed_Reads/*P1*>;
	open my $lib_out, ">", $name . "_lib.txt";
	my $lib_counter=1;
	for my $p1file (@p1_temp){
			my $libc ="lib" . $lib_counter;
			my $short_p1=$p1file;
			my $short_p2 = $short_p1;
			$short_p2 =~ s/P1/P2/;
			print $lib_out "$libc\t$short_p1\t$short_p2\t300\t0.75\tFR\n";
	} 
	close $lib_out;
	my $sspace_build_exec = "perl " . $SSPACE ." -l " . $name."_lib.txt -s " .$_[0] . " -k 1 -g 1 -b" . $_[1];
	system($sspace_build_exec);
	
	my $scaffolded_assembly = "Scaffolding/".$name . ".final.scaffolds.fasta";

	chdir ("../");
	return($scaffolded_assembly);

}


##########
sub count_contigs {
	my %contig_lengths;
	my $afin_contig;
	my $lmax_afin=0;
	my $lmin_afin=100000000;

	open my $afin_file, "<", $_[0];
	while(<$afin_file>){
		chomp;
		if(/>/){
			if(/len_(\d+)/){
			my $afinlen=$1;
			if($lmax_afin < $afinlen){
				$lmax_afin = $afinlen;
			}
			if($lmin_afin > $afinlen){
				$lmin_afin = $afinlen;
			}
			$contig_lengths{$_}=$afinlen;
			}
			else{
			$contig_lengths{$_}=1;
			}
		}
	}
	my $total_afin_contigs = keys %contig_lengths;
	return ($total_afin_contigs);
}
#########
sub run_afin {
	###Sub must be given number of iterations, trim length, and number of reads needed to fuse contigs.
	my $extension = $_[5];
	my $afin_exec = $AFIN_DIR . "/afin -c " . $_[4] . " -r ../Trimmed_Reads/" . $name .".trimmed* -l " . $_[0] . " -f .1 -d " . $_[1] . " -x " . $extension . " -p " . $_[2] . " -i " . $_[3] ." -o ". $name . "_afin";
	print "Using command $afin_exec.\n";
	system($afin_exec);

	my %contig_lengths;
	my $afin_contig;
	my $max_afin=0;
	my $min_afin=100000000;

	open my $afin_file, "<", $name . "_afin_iter0.fa";
	while(<$afin_file>){
		chomp;
		if(/>/){
			/len_(\d+)/;
			my $afinlen=$1;
			$contig_lengths{$_}=$afinlen;
			if($max_afin < $afinlen){
				$max_afin = $afinlen;
			}
			if($min_afin > $afinlen){
				$min_afin = $afinlen;
			}
		}
	}
	my $total_afin_contigs = keys %contig_lengths;
	return ($total_afin_contigs, $max_afin, $min_afin);
}

##########

sub cpgene_recovery {
	$current_runtime = localtime(); 
	
	print "$current_runtime\tChecking chloroplast gene recovery in contigs.\n";
	my $current_afin = $_[0];
	my %chloroplast_db_genes;
	open my $cpdbgenes, "<", $FPBIN . "/Angiosperm_Chloroplast_Genes.fsa";
	while(<$cpdbgenes>){
		chomp;
		if(/>/){
			/>(.*?)\_/;
			$chloroplast_db_genes{$1}=1;
		}
	}
	`$BLAST/makeblastdb -in $FPBIN/Angiosperm_Chloroplast_Genes.fsa -dbtype nucl`;
	my $blast_afin_exec = $BLAST . "blastn -query " . $current_afin . " -db " . $posgenes . " -evalue 1e-40 -outfmt 6 -max_target_seqs 1000000 > " . $current_afin."_positional_genes" . ".blastn";
	`$blast_afin_exec`;
	my $total_chloroplast_db_genes= scalar keys %chloroplast_db_genes;

	my %hit_chloroplast_db_genes;
	my %contigs_db_genes;
	open my $hitcpdbgenes, "<", $current_afin . "_positional_genes" .".blastn";
	while(<$hitcpdbgenes>){
		chomp;
		my @tarray = split /\s+/;
		$tarray[1] =~ /(.*?)\_/;
		$hit_chloroplast_db_genes{$1}=1;
		$contigs_db_genes{$tarray[0]}{$1}=1;
	}
	my $total_hit_chlorplast_db_genes= scalar keys %hit_chloroplast_db_genes;
	my $percent_recovered_genes = $total_hit_chlorplast_db_genes/$total_chloroplast_db_genes;

	
	return ($percent_recovered_genes, \%contigs_db_genes);

	
}

##########

sub remove_nested {
        
        my $temp_contigsfile = $_[0]; #fasta file of contigs that were blasted against themselves
        my $temp_blastfile = $_[1]; #blast file of self blast
        my %delete_contigs;
        my %blast_scores;
        my %temp_seqs;

        my $tesid;
        open my $tsfile, "<", $temp_contigsfile;
        while(<$tsfile>){
                chomp;
                if(/>/){
                        $tesid = substr($_, 1);
                }
                else{
                        $temp_seqs{$tesid}.=$_;
                }
        }

        open my $checkblast, "<", $temp_blastfile;
        while(<$checkblast>){
                chomp;
                my @tarray = split /\s+/;
                if($tarray[0] eq $tarray[1]){
                        next;
                }
                my $len1 = length($temp_seqs{$tarray[0]});
                my $len2 = length($temp_seqs{$tarray[1]});

                my $max = 0;
                my $min = 0;

                if ($len1 > $len2){
                        $max = $len1;
                        $min = $len2;
                }
                else{
                        $max = $len2;
                       $min =  $len1;
                }

                if($max == $len1){
                        next;
                }

                my $qstart;
                my $qstop;
                my $qhit = $tarray[7]-$tarray[6];
                
                if($qhit < 0){
                        $qstart=$tarray[7];
                        $qstop=$tarray[6];
                        $qhit=abs($qhit);
                }
                else{
                        $qstart=$tarray[6];
                        $qstop=$tarray[7];
                }

                my $shit = $tarray[9]-$tarray[8];
                if(exists $blast_scores{$tarray[0]}{$tarray[1]}){
                        for (my $i=$qstart-1; $i <= ($qstop-1); $i++){
                                @{$blast_scores{$tarray[0]}{$tarray[1]}}[$i]++;
                        }
                }
                elsif(exists $blast_scores{$tarray[1]}{$tarray[0]}){
                        for (my $i=$qstart-1; $i <= ($qstop-1); $i++){
                                @{$blast_scores{$tarray[0]}{$tarray[1]}}[$i]++;
                        }
                }
                else{
                        for (my $j=0; $j<$min; $j++){
                                @{$blast_scores{$tarray[0]}{$tarray[1]}}[$j]=0;
                        }
                        for (my $i=$qstart-1; $i <= ($qstop-1); $i++){
                                @{$blast_scores{$tarray[0]}{$tarray[1]}}[$i]++;
                        }
                }
        }
        
        for my $blastid1 (keys %blast_scores){
                for my $blastid2 (keys %{$blast_scores{$blastid1}}){
                        my $overlap;
                        for my $i (@{$blast_scores{$blastid1}{$blastid2}}){
                                if($blast_scores{$blastid1}{$blastid2}[$i] > 0){
                                        $overlap ++;
                                }
                        }
                        

                        my $len_min = length($temp_seqs{$blastid1});
                        if ($overlap/$len_min >= 0.9){
                                $delete_contigs{">".$blastid1}=0;
                        }

                }

        }

        open my $afinout, ">", $temp_contigsfile . "_fixed";
        open my $oldafin, "<", $temp_contigsfile;

        my $tempsid;
        while(<$oldafin>){
                chomp;
                if(/>/){
                        if(exists $delete_contigs{$_}){;
                                $tempsid=();
                                next;
                        }
                        else{
                                $tempsid=$_;
                                print $afinout  "$tempsid\n";
                        }
                }
                elsif($tempsid){
                        print $afinout "$_\n";
                }
        }

        `mv $temp_contigsfile\_fixed $temp_contigsfile`;

}

##########

sub orientate_plastome{
        
        my $current_afin = $_[0];
        my $name = $_[1];

        `$BLAST/makeblastdb -in $posgenes -dbtype nucl`;

        for (my $i = 0; $i <=3; $i++){

        	`perl $FPBIN/sequence_based_ir_id.pl ../Afin_Assembly/$current_afin $name $i`;
        	my $split_fullname= $name ."_regions_split".$i.".fsa";

        	`$BLAST/makeblastdb -in $split_fullname -dbtype nucl`;
        	my $blast_afin_exec = $BLAST . "blastn -query " . $split_fullname . " -db " . $split_fullname . " -evalue 1e-40 -outfmt 6 -max_target_seqs 1000000 > " . $split_fullname . ".blastn";
			system($blast_afin_exec);

			remove_nested($split_fullname,$split_fullname.".blastn");

			my $chloroplast_pieces = &count_contigs($split_fullname);

			if($chloroplast_pieces < 2){
				next;
			}

			$blast_afin_exec = $BLAST . "blastn -query " . $split_fullname . " -db " . $posgenes . " -evalue 1e-40 -outfmt 6 -max_target_seqs 1000000 > " . $split_fullname . "_positional_genes" . ".blastn";
			system($blast_afin_exec);
			my ($percent_recovered_genes, $contigs_db_genes) = &cpgene_recovery($split_fullname);
			my %contigs_db_genes = %$contigs_db_genes;
			$percent_recovered_genes=$percent_recovered_genes*100;

			if($percent_recovered_genes > .9){
					`perl $FPBIN/orientate_plastome_v.2.0.pl $split_fullname $current_afin\_positional_genes.blastn $name`;
        			my $final_seq = $name ."_FULLCP.fsa";
        			$blast_afin_exec = $BLAST . "blastn -query " . $final_seq . " -db " . $posgenes . " -evalue 1e-40 -outfmt 6 -max_target_seqs 1000000 > " . $current_afin . "_positional_genes" . ".blastn";
        			system($blast_afin_exec);
        			($percent_recovered_genes, $contigs_db_genes) = &cpgene_recovery($split_fullname);
        			%contigs_db_genes = %$contigs_db_genes;
        			$percent_recovered_genes=$percent_recovered_genes*100;

        			open my $cpcomposition, ">", "Chloroplast_gene_composition_of_final_chloroplast_sequence.txt";
                    for my $contig_name (sort keys %contigs_db_genes){
                        for my $gene_name (sort keys %{$contigs_db_genes{$contig_name}}){
                            print $cpcomposition "$contig_name\t$gene_name\n";
                        }
                    }
                    close ($cpcomposition);
                    return; #bad form to have multiple exits but i haven't worked out the "correct" way yet
			}
		}


}

        

########## USAGE BELOW ##########
=pod

=head1 Fast-Plast: Rapid de novo assembly and finishing for whole chloroplast genomes

fast-plast.pl

=head1 USAGE

    fast-plast.pl [-1 <paired_end_file1> -2 <paired_end_file2> || -single <singe_end_file>] -name <sample_name> [options] 
or
    fast-plast.pl -help

Required options:
	
	-1 <filenames>	 		File with forward paired-end reads. Multiple files can be designated with a comma-delimited list. Read files should be in matching order with other paired end files.
	-2 <filenames> 	 		File with reverse paired-end reads. Multiple files can be designated with a comma-delimited list. Read files should be in matching order with other paired end files.
	-s <filenames>	 		File with unpaired reads. Multiple files can be designated with a comma-delimited list.

	PAIRED END AND/OR SINGLE END FILES CAN BE PROVIDED SIMULTAENOUSLY.

	-n <sample_name> 		Name for current assembly. We suggest a species name/accession combination as Fast-Plast will use this name as the FASTA ID in the final assembly.

Advanced options:

	--threads				Number of threads used by Fast-Plast.  [Default = 4]
	--adapters				Files of adapters used in making sequencing library. [Default = NEB-PE]
	--bowtie_index   		User defined bowtie2 index for mapping step. Useful for non-angiosperm or unrespesented taxa in the default index. [Default = Verdant]
	--posgenes  	 		User defined genes for identification of single copy/IR regions and orientation. Useful when major rearrangments are present in user plastomes.
	--coverage_analysis     Flag to run the coverage analysis of a final chloroplast assembly.

=head1 DESCRIPTION

Fast-Plast is a pipeline that leverages existing and novel programs to quickly assemble, orient, and verify whole chloroplast genome sequences. For most datasets with sufficient data, Fast-Plast is able to produce a full-length de novo chloroplast genome assembly in approximately 30 minutes with no user mediation. 

Currently, Fast-Plast is written to accomodate Illumina data, though most data types could be used with a few changes.

Fast-Plast uses a de novo assembly approach by combining the de bruijn graph-based method of SPAdes with an iterative seed-based assembly implemented in afin to close gaps of contigs with low coverage. The pipeline then identifies regions from the quadripartite structure of the chloroplast genome, assigns identity, and orders them according to standard convention. A coverage analysis is then conducted to assess the quality of the final assembly. 

=head1 REQUIREMENTS

Fast-Plast requires Trimmomatic, bowtie2, SPAdes, and BLAST+.

If you use the coverage analysis to verify the assembly, then Jellyfish 2 and R will be needed. We highly recommend the coverage analysis to check the Fast-Plast assembly. 

afin requires a c++ complier with c++11 support and zlib.h.  zlib.h is a standard base library for most *nix systems. See https://github.com/mrmckain/Fast-Plast for help with installation.

Fast-Plast is coded to use 4 threads during the Trimmomatic, bowtie2, SPAdes, and afin steps. This can simply be changed by the user if this number is not available.

Memory requirements will vary based on the size of your data set. Expect to use 1.5-2x the memory for the size of your reads files. If your data set is exceptionally large, we have found success in reducing the dataset to 50 million reads and running them through Fast-Plast.

=head1 INSTALLATION

All required programs should be in the user's path. 

To install afin:

		cd afin
		make





=cut