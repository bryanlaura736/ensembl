# Ensembl module for Bio::EnsEMBL::DBSQL::Utils
#
# Written by Arek Kasprzyk
#
# Copyright GRL and EBI
#
# You may distribute this module under the same terms as perl itself
# POD documentation - main docs before the code



=head1 NAME

Bio::EnsEMBL::DBSQL::Utils - Module having the fset2transcript subroutines

=head1 SYNOPSIS

    use Bio::EnsEMBL::DBSQL::Utils;

    &Bio::EnsEMBL::DBSQL::Utils::fset2transcript($fset_id);

=head1 DESCRIPTION

Module containing the sub routine fset2transcript, 
which creates transcripts from features


=head1 CONTACT

Ensembl - ensembl-dev@ebi.ac.uk


=head1 CONTACT

Ensembl - ensembl-dev@ebi.ac.uk

=head1 APPENDIX

The rest of the documentation details each of the object methods. Internal methods are usually preceded with a _

=cut



package Bio::EnsEMBL::DBSQL::Utils;
use Bio::EnsEMBL::DBSQL::Obj;
use strict;



sub fset2transcript {
    my ($genscan,$contig)=@_;

  
    unless ($genscan->isa ("Bio::EnsEMBL::SeqFeatureI"))
    {print "$genscan must be Bio::EnsEMBL::SeqFeatureI\n";}
    unless ($contig->isa ("Bio::EnsEMBL::DB::ContigI"))
    {print "$contig must be Bio::EnsEMBL::DB::ContigI\n";}

    
    my $transcript = new Bio::EnsEMBL::Transcript;
    $transcript->id($contig->id . "." . $genscan->raw_seqname);
        
    my @exons;
    my $count= 1;
    
    foreach my $f ($genscan->sub_SeqFeature) {
	
	my $exon  = new Bio::EnsEMBL::Exon;
	$exon->id       ($contig->id . "." .$count);
	$exon->contig_id($contig->id);
	$exon->start    ($f->start);
	$exon->end      ($f->end  );
	$exon->strand   ($f->strand);
	$exon->attach_seq($contig->primary_seq);
	
	push(@exons,$exon);
	$count++;
	
    }
    
    my $translation = new Bio::EnsEMBL::Translation;
    $translation->id($contig->id.".".$genscan->raw_seqname);
    
    if ($exons[0]->strand == 1) {
	@exons = sort {$a->start <=> $b->start} @exons;
	$translation->start        ($exons[0]->start);
	$translation->end          ($exons[$#exons]->end);
	
    } else {
	@exons = sort {$b->start <=> $a->start} @exons;
	$translation->start        ($exons[0]->end);
	$translation->end          ($exons[$#exons]->start);
	
    }
    
    $translation->start_exon_id($exons[0]->id);
    $translation->end_exon_id  ($exons[$#exons]->id);
    
	my $endphase = 0;
    
    foreach my $exon (@exons) {
	
	$exon->phase         ($endphase);
	$transcript->add_Exon($exon);
	$endphase = $exon->end_phase;
	
    }
    
    $transcript->translation($translation);
    
    return $transcript;
}

1;






























