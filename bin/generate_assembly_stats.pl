#use strict;
use warnings;
use Statistics::Basic qw(:all);

#####################################################
#Display information about the constructed scaffolds for downstream analysis.
#####################################################

#First we get the total number of contigs for each cluster
my ($scaffold_file, $cluster_file, $coverage_file, $species_file, $strain_dir, $scaffold_seq_file, $outfile, $opera_ms_dir, $nb_process, $mummer_dir) = @ARGV;

my $use_nucmer = 0;
    

print STDERR " *** Reading coverage file $coverage_file\n";
my %contig_cov = ();
read_coverage_file(\%contig_cov, $coverage_file);

my %clusters_to_contigs = ();
read_cluster_file(\%clusters_to_contigs, $cluster_file);

my %cluster_to_species = ();
if($species_file ne "NULL"){
    print STDERR " *** Reading reference clustering file $species_file\n";
    read_species_file(\%cluster_to_species, $species_file);
}

my %filled_scaffold_length = ();
analyse_scaff_seq(\%filled_scaffold_length, \%cluster_to_species, \%clusters_to_contigs, $scaffold_file, $scaffold_seq_file, $use_nucmer);

write_assembly_stats(\%filled_scaffold_length, \%cluster_to_species, \%clusters_to_contigs, \%contig_cov, $scaffold_file, $strain_dir, $outfile);

sub write_assembly_stats{
    my ($filled_scaffold_length, $cluster_to_species, $clusters_to_contigs, $contig_cov, $scaffold_file,  $strain_directory, $outfile) = @_;
    my @cov_list = [];
    my $species_info_line = "";
    my ($ref_genome, $species_name);
    my %nb_species_strain = ();
    my $scaff_name = "";
    my $cluster_for_scaffold = undef;
    my @scaff_delim;
    my ($scaff_id, $median_cov, $length, $str_scaff);

    open (OUTFILE, '>', $outfile) or die;
    print OUTFILE "SEQ_ID\tLENGTH\tARRIVAL_RATE\tSPECIES\tNB_STRAIN\tREFERENCE_GENOME\n";
    open (SCAFFOLDS, $scaffold_file) or die;
    
    while(<SCAFFOLDS>){
	chomp $_;
	my @line = split(/\t/, $_);
	my $contig = $line[0];
	my $next_scaffold = $_;

	if ($_ =~ />/){
	    if ($scaff_name ne ""){
		$median_cov = median(@cov_list);
		#print STDERR " *** $scaffold_name\n";<STDIN>;# @cov_list . "\n";
		$length= $filled_scaffold_length{$scaff_name};
		
		$str_scaff = get_scaffold_info($scaff_name, $cluster_for_scaffold, $median_cov, $length, $cluster_to_species, \%nb_species_strain, $strain_directory);
		print OUTFILE $str_scaff;
		#$scaf_name =~ /length:\s(\d*)\s/;
	    }

	    $numb_contigs_in_scaffold = 0; 
	    $scaff_name = $next_scaffold;
	    $cluster_for_scaffold = undef;
	    undef(@cov_list);
	}

	else{
	    #if contig is less than 500 bp, it will not exist in the clusters file.
	    if (!exists($clusters_to_contigs->{$contig})) {  next; }
	    $numb_contigs_in_scaffold++;
	    $cluster_for_scaffold = $clusters_to_contigs->{$contig};
	    push @cov_list, $contig_cov->{$contig};
	}

    }

    #For the lats scaffold
    $median_cov = median(@cov_list);
    $length= $filled_scaffold_length{$scaff_name};
    $str_scaff = get_scaffold_info($scaff_name, $cluster_for_scaffold, $median_cov, $length, $cluster_to_species, \%nb_species_strain, $strain_directory);
    print OUTFILE $str_scaff;
    
    close(SCAFFOLDS);
    close(OUTFILE);
}


sub get_scaffold_info{
    my ($scaff_name, $cluster_for_scaffold, $median_cov, $length, $cluster_to_species, $nb_species_strain, $strain_directory) = @_;
    @scaff_delim = split(/\t/, $scaff_name);
    $scaff_id = $scaff_delim[0];
    my $scaffold_name = substr($scaff_id,1);
    
    #print STDERR " *** $scaffold_name\n";<STDIN>;# @cov_list . "\n";
    $length= $filled_scaffold_length{$scaffold_name};
    my $no_species_info_line = "NA\tNA\tNA";
    my $str_res = "";
    my $species_info_line;
    if (defined($cluster_for_scaffold)){
	$str_res = $scaff_id . "\t$length\t$median_cov\t";
    }
    else{
	$str_res = $scaff_id . "\t$length\tNA\t";
    }
    #print STDERR " **** $scaf_name $length\n";
    if (1 || $length > 999){
	
	if (defined $cluster_for_scaffold && exists $cluster_to_species->{$cluster_for_scaffold}){
	    $species_info_line = "";
	    
	    #Get the species name
	    $ref_genome = $cluster_to_species->{$cluster_for_scaffold};
	    @tmp = split(/\//, $ref_genome);
	    @tmp_2 = split(/\_/,$tmp[@tmp-2]);
	    $species_name = $tmp_2[0] . "_" . $tmp_2[1];
	    if(! exists $nb_species_strain->{$species_name}){
		$nb_s = 1;
		$s_s_dir = "$strain_directory/$species_name";
		if(-d $s_s_dir){
		    #print STDERR "ll $s_s_dir/STRAIN_*/contigs.fa/n";
		    $nb_s = `ls -l $s_s_dir/STRAIN_*/contigs.fa | wc -l`;chop $nb_s;
		}
		$nb_species_strain->{$species_name} = $nb_s;
	    }
	    
	    $str_res .= $species_name . "\t" . $nb_species_strain->{$species_name} . "\t" . "$opera_ms_dir/$ref_genome";
	}

	else{
	    $str_res .= $no_species_info_line;
	}
    }
    
    else{
	$str_res .= $no_species_info_line;
    }
    $str_res .= "\n";
}

sub analyse_scaff_seq{
    my ($filled_scaffold_length, $clusters_to_contigs, $cluster_to_species, $scaffold_file, $scaffold_seq_file, $use_nucmer) = @_;
    #Now we associate each scaffold with a cluster, and find out how many contigs
    #from that scaffold are associated with the cluster
    open (SCAFFOLDS, $scaffold_file) or die;
    open (SCAFFOLDSEQ, $scaffold_seq_file) or die;

    my $scaf_name = "";
    my $numb_contigs_in_scaffold = 0;
    my $cluster_for_scaffold; 
    my $scaffold_name;
    my $scaffold_seq;
    
    #Preprocessing for nucmer.
    my $CMD;
    if($use_nucmer){
	my $cmd_file = "$ref_directory/POST_EVAL/cmd.txt";
	print STDERR "mkdir -p $ref_directory/POST_EVAL/\n";
	`rm -r $ref_directory/POST_EVAL/;mkdir -p $ref_directory/POST_EVAL/`;
	open ($CMD, ">",  $cmd_file) or die;
    }
    #print STDERR " *** Run nucmmer\n";
    
    
    while (<SCAFFOLDS>){
	chomp $_;
	if ($_ =~ />/){
	    my @line = split(/\t/, $_);
	    $_ =~ /length:\s(\d*)\s/;
	    my $length = $1;

	    my $scaffold = $line[0];
	    my $scaffname = substr $scaffold,1;

	    $scaffold_name = <SCAFFOLDSEQ>;
	    $scaffold_seq = <SCAFFOLDSEQ>;
	    
	    $length = length($scaffold_seq) - 1;
	    $filled_scaffold_length->{$scaffname} = $length;
	    #
	    #print STDERR " *** *** $scaffold_name $scaffname $length\n";#<STDIN>;
	    
	    #Make intermediate files for nucmer only for large enough scaffolds.
	    if($use_nucmer && $length > 999){
		
		open (SCAF_OUT, ">", "$ref_directory/POST_EVAL/$scaffname") or die;
		print SCAF_OUT $scaffold_name;
		print SCAF_OUT $scaffold_seq;
		close (SCAF_OUT);
		my @contigline = split(/\t/, <SCAFFOLDS>);
		my $contig = $contigline[0];
		print STDERR $contig . "\n";
		my $cluster_for_scaffold = $clusters_to_contigs->{$contig};
		if (defined $cluster_for_scaffold and
		    exists $cluster_to_species->{$cluster_for_scaffold}){
		    my $command = "${mummer_dir}nucmer --maxmatch -c 400 --banded $ref_directory/POST_EVAL/$scaffname $opera_ms_dir/$cluster_to_species{$cluster_for_scaffold} -p $ref_directory/POST_EVAL/$scaffname; ${mummer_dir}show-coords -lrcT $ref_directory/POST_EVAL/$scaffname.delta > $ref_directory/POST_EVAL/$scaffname-out\n"; 
		    print CMD $command;
		}
	    }
	}
    }
    close(SCAFFOLDS) or die;
    close(SCAFFOLDSEQ) or die;
    close(CMD);
    if ($use_nucmer){
	#exit(0);
	#Go through and parse the scaffolds file and the nucmer.
	my $command = "cat $cmd_file | xargs -L 1 -P $nb_process -I COMMAND sh -c \"COMMAND\" 2> $cmd_file-log.txt";
	print STDERR $command . "\n";
	`$command`;
    }
}

sub read_cluster_file{
    my ($clusters_to_contigs, $cluster_file) = @_;
    open (CLUSTERS, $cluster_file) or die;
    while (<CLUSTERS>){
	chomp $_;
	my @line = split(/\t/, $_);
	my $contig = $line[0];
	my $cluster = $line[1];
	$clusters_to_contigs{$contig} = $cluster;
    }
    close(CLUSTERS);
}

sub read_species_file{
    my ($cluster_to_species, $species_file) = @_;
    open (SPECIES, $species_file) or die;
    my $cluster_name = "";
    my $best_species = "";
    while(<SPECIES>){
	chomp $_;
	if ($_ =~ />(.*)/){
	    if ($cluster_name ne ""){
		$cluster_to_species->{$cluster_name} = $best_species if ($best_species ne ""); 
	    #print STDERR "$best_species, $cluster_name\n";
	    }
	    #print STDERR $1 . "\n";
	    $cluster_name = $1;
	    $best_species = "";
	}

	else{
	    if ($best_species eq ""){
		$best_species = $_;
	    }
	}
    }
}

sub read_coverage_file{
    my ($contig_cov, $contigs_windows_file) = @_;
    open (FILE, $contigs_windows_file) or die "$contigs_windows_file not found";
    my $header = <FILE>;
    chomp $header;
    my @line = split (/ /, $header);
    my $window_size = $line[3];
    while (<FILE>) {
	chomp $_;	
	#The line with the contig ID
	my @line = split (/\t/, $_);
	my $contig = $line[0];
	my $length = $line[1];
	my $nb_window = $line[4];
	#The line with number of arriving reads
	my $read_count = <FILE>;
	chop $read_count;
	#print STDERR $read_count."\t|".$nb_window."|\t".$window_size."\n";<STDIN>;
	#Skip the next line that contian the windows (need to compute the variance latter)
	my $str = <FILE>;chop $str;
	$contig_cov->{$contig} = $read_count/($nb_window*$window_size);
    }
}

sub get_species_metrics{
    my ($cluster, $species, $dir) = @_; 
    my $mashfile = "$dir/MASH/$cluster.dat";
    my $metrics = "";
    open (MASHFILE, $mashfile) or die("$cluster, $species, $dir"); 

    while (<MASHFILE>){
        chomp $_;
        my @line = split(/\t/, $_);
        if ($line[0] eq $species){
            $metrics = "C-$cluster;$line[2];$line[4]";
        }
    }

    close (MASHFILE);

    return $metrics;
}

sub get_nucmer_info{
    my ($length, $scaffold) = @_;
    #print STDERR "$ref_directory/POST_EVAL/$scaffold-out\n";
    my $aligned_length;
    my $ref_length;
    my $percent_scaff_align;
    my $identity_weighted;
    #print STDERR " *** Read file $ref_directory/POST_EVAL/$scaffold-out\n";
    open (NUCMER_INFO, "$ref_directory/POST_EVAL/$scaffold-out") or die " *** File $scaffold-out not found\n";
    <NUCMER_INFO>;
    <NUCMER_INFO>;
    <NUCMER_INFO>;
    <NUCMER_INFO>;

    while(<NUCMER_INFO>){
        chomp $_;
        my @line = split(/\t/, $_);
        $ref_length = $line[8];
        $aligned_length += $line[4];
        $identity_weighted += $line[6] * $line[4]; 
    }

    if(defined $aligned_length){
        $percent_scaff_align = $aligned_length / $length;
    }

    else{
        return "NA\tNA";
    }

    $identity_weighted = $identity_weighted / $aligned_length;

    my $percent_ref_covered = $aligned_length/$ref_length;
    return "$percent_scaff_align\t$identity_weighted";
    #return "$ref_length\t$aligned_length\t$percent_ref_covered\t$percent_scaff_align\t$identity_weighted\t";
}