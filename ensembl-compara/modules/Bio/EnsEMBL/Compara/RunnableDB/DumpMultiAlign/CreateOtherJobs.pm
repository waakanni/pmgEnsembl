
=pod 

=head1 NAME

Bio::EnsEMBL::Hive::RunnableDB::DumpMultiAlign::CreateOtherJobs

=head1 SYNOPSIS

This RunnableDB module is part of the DumpMultiAlign pipeline.

=head1 DESCRIPTION

This RunnableDB module generates DumpMultiAlign jobs from genomic_align_blocks
on the chromosomes which do not contain species. The jobs are split into 
$split_size chunks

=head1 CONTACT

This modules is part of the EnsEMBL project (http://www.ensembl.org)

Questions can be posted to the ensembl-dev mailing list:
ensembl-dev@ebi.ac.uk

=cut


package Bio::EnsEMBL::Compara::RunnableDB::DumpMultiAlign::CreateOtherJobs;

use strict;
use Bio::EnsEMBL::Hive::DBSQL::AnalysisDataAdaptor;
use base ('Bio::EnsEMBL::Compara::RunnableDB::BaseRunnable');

use POSIX qw(ceil);

=head2 strict_hash_format

    Description : Implements strict_hash_format() interface method of Bio::EnsEMBL::Hive::Process that is used to set the strictness level of the parameters' parser.
                  Here we return 0 in order to indicate that neither input_id() nor parameters() is required to contain a hash.

=cut

sub strict_hash_format {
    return 0;
}


sub fetch_input {
    my $self = shift;
}


sub run {
    my $self = shift;
    

}

sub write_output {
    my $self = shift @_;
    my $reg = "Bio::EnsEMBL::Registry";
    my $output_ids;
    my $compara_dba;

    #
    #Load registry and get compara database adaptor
    #
    if ($self->param('reg_conf')) {
	Bio::EnsEMBL::Registry->load_all($self->param('reg_conf'),1);
	$compara_dba = Bio::EnsEMBL::Registry->get_DBAdaptor($self->param('compara_dbname'), "compara");
    } elsif ($self->param('compara_url')) {
	#If define compara_url, must also define core_url(s)
	Bio::EnsEMBL::Registry->load_registry_from_url($self->param('compara_url'));
	if (!defined($self->param('core_url'))) {
	    $self->throw("Must define core_url if define compara_url");
	}
	my @core_urls = split ",", $self->param('core_url');

	foreach my $core_url (@core_urls) {
	    Bio::EnsEMBL::Registry->load_registry_from_url($self->param('core_url'));
	}
	$compara_dba = Bio::EnsEMBL::Compara::DBSQL::DBAdaptor->new(-url=>$self->param('compara_url'));
    } else {
	Bio::EnsEMBL::Registry->load_all();
	$compara_dba = Bio::EnsEMBL::Registry->get_DBAdaptor($self->param('compara_dbname'), "compara");
    }

    my $tag = "other";

    my $output_file = $self->param('output_dir') ."/" . $self->param('filename') . "." . $tag . "." . $self->param('format');

    #Convert human to Homo sapiens
    #my $species_name = $reg->get_adaptor($self->param('species'), "core", "MetaContainer")->get_Species->binomial;
    my $species_name = $reg->get_adaptor($self->param('species'), "core", "MetaContainer")->get_production_name;

    my $mlss_adaptor = $compara_dba->get_MethodLinkSpeciesSetAdaptor;
    my $gab_adaptor = $compara_dba->get_GenomicAlignBlockAdaptor;

    my $mlss = $mlss_adaptor->fetch_by_dbID($self->param('mlss_id'));
    my $dump_mlss_id = $self->param('dump_mlss_id');

    #
    #Find genomic_align_blocks which do not contain $self->param('species')
    #(usually human)
    #
    my $skip_genomic_align_blocks = $gab_adaptor->
      fetch_all_by_MethodLinkSpeciesSet($mlss);
    for (my $i=0; $i<@$skip_genomic_align_blocks; $i++) {
	my $has_skip = 0;
	foreach my $this_genomic_align (@{$skip_genomic_align_blocks->[$i]->get_all_GenomicAligns()}) {
	    if (($this_genomic_align->genome_db->name eq $species_name) or
		($this_genomic_align->genome_db->name eq "Ancestral sequences")) {
		$has_skip = 1;
		last;
	    }
	}
	if ($has_skip) {
	    my $this_genomic_align_block = splice(@$skip_genomic_align_blocks, $i, 1);
	    $i--;
	    $this_genomic_align_block = undef;
	}
    }
    my $dump_program = $self->param('dump_program');
    my $dump_mlss_id = $self->param('dump_mlss_id');
    my $reg_conf = $self->param('reg_conf');
    my $compara_dbname = $self->param('compara_dbname');
    my $masked_seq = $self->param('masked_seq');
    my $split_size = $self->param('split_size');
    my $format = $self->param('format');
    my $species = $self->param('species');
    my $emf2maf_program = $self->param('emf2maf_program');
    my $maf_output_dir = $self->param('maf_output_dir');

    my $gab_num = 1;
    my $start_gab_id ;
    my $end_gab_id;
    my $chunk = 1;

    #
    #Create a table (other_gab) to store the genomic_align_block_ids of those
    #blocks which do not contain $self->param('species')
    #
    foreach my $gab (@$skip_genomic_align_blocks) {
	my $sql_cmd = "INSERT INTO other_gab (genomic_align_block_id) VALUES (?)";
	my $dump_sth = $self->analysis->adaptor->dbc->prepare($sql_cmd);
	$dump_sth->execute($gab->dbID);
	$dump_sth->finish();

	if (!defined $start_gab_id) {
	    $start_gab_id = $gab->dbID;
	}

	#Create jobs after each $split_size gabs
	if ($gab_num % $split_size == 0 || 
	    $gab_num == @$skip_genomic_align_blocks) {

	    $end_gab_id = $gab->dbID;

	    my $this_num_blocks = $split_size;
	    if ($gab_num == @$skip_genomic_align_blocks) {
		$this_num_blocks = (@$skip_genomic_align_blocks % $split_size);
	    }

	    my $this_suffix = "_" . $chunk . "." . $format;
	    my $dump_output_file = $output_file;
	    $dump_output_file =~ s/\.$format/$this_suffix/;

	    #Write out cmd from DumpMultiAlign
	    my $dump_cmd = "\"cmd\"=>\"perl $dump_program --reg_conf $reg_conf --dbname $compara_dbname --mlss_id $dump_mlss_id --skip_species $species --masked_seq $masked_seq --split_size $split_size --output_format $format --output_file $output_file --chunk_num $chunk\", \"num_blocks\"=>\"$this_num_blocks\", \"output_file\"=>\"$dump_output_file\", \"format\"=> \"$format\", \"emf2maf_program\"=>\"$emf2maf_program\", \"maf_output_dir\"=>\"$maf_output_dir\"";

	    #Used to create a file of genomic_align_block_ids to pass to
	    #DumpMultiAlign
	    my $output_ids = "{\"start\"=>\"$start_gab_id\", \"end\"=>\"$end_gab_id\", $dump_cmd}";

	    #print "skip $output_ids\n";
	    $self->dataflow_output_id($output_ids, 2);
	    undef($start_gab_id);
	    $chunk++;
	}
	$gab_num++;
    }
}


1;