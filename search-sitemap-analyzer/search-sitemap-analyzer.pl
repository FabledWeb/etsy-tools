use strict;
use warnings;
use URI;
use WWW::SitemapIndex::XML;
use Data::Dumper;

print Dumper(analyzeQueries(getQueries()));

sub analyzeQueries {
  my @queries = @_;

  my $unfiltered_total= scalar @queries;

  my @words= map {split ' '} @queries;
  my $unfiltered_words_total= scalar @words;

  my $filter= $ARGV[1];
  my $rank=0;
  my %ranked= map {$rank++;{$_ => $rank}} @queries;

  @queries= grep { /$filter/i } @queries if $filter;
  @words= map {split ' '} @queries;

  my @sorted = map {{q => $_, rank => $ranked{$_}}} @queries;
  my @sorted_words = getSortedByCount(\@words);

  my $limit= $ARGV[2] || 20;
  my @top= grep {$_} @sorted[0..$limit-1];
  my @top_words= grep {$_} @sorted_words[0..$limit-1];

  return {
    filtered_by => $filter,
    searches => {
      unfiltered_total => $unfiltered_total,
      total => scalar @queries,
      total_unique => scalar @sorted,
      top => \@top,
    },
    keywords => {
      unfiltered_total => $unfiltered_words_total,
      total => scalar @words,
      total_unique => scalar @sorted_words,
      top => \@top_words,
    },
    max => $limit,
  };
}

sub getSortedByCount {
  my $list= shift;
  my %counts= ();
  $counts{$_}++ for @$list;
  return map{{$_ => $counts{$_}}} sort {$counts{$b} <=> $counts{$a}} keys %counts;
}

sub getQueries {
  my $index = WWW::SitemapIndex::XML->new;
  $index->load(location => $_) for glob($ARGV[0]);
  return map {my %form= URI->new($_->loc)->query_form; lc $form{'q'}} $index->sitemaps;
}
