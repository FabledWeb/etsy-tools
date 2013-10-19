#!/usr/bin/perl
#
# $Header: P:\\RCS\\S\\comsite4\\bin\\utilities\\Keyphrase.pm,v 1.3 2007/05/04 17:41:36 ecanales Exp $
#
# Module to handle extracting keypharases.
#
# Routines:
#  ExtractKeyphrasesFromHTML
#  ExtractKeyphrasesFromText
#

package Keyphrase;
use strict;


sub ExtractKeyphrasesFromHTML
{
	my ($content, $title_array_ref, $headings_hash_ref, $keywords_hash_ref, $stopwords_array_ref, $max, $min_length, $phrase_length);
	
	#2.1 get all titles
	while($content=~ m{<title>(.*?)</title>}gis)
	{
		push (@{$title_array_ref}, $1);
	}
	
	#2.2 get all headings
	while($content=~ m{<h(\d)>(.*?)</h.>}igs)
	{
		$$headings_hash_ref{"$2"}= $1;
	}
	
	#2.3 get just the body (can't use m{<body.*?>(.*?)</body>}i;
	#    because </body> doesn't always exist).
	$content=~ s{<head>.*?</head>}{}gis; #remove head section
	$content=~ s{<title>.*?</title>}{}gis; #remove title
	#$content=~ s{<h.>.*?</h.>}{}gis; #remove headings
	$content=~ s{<script.*?</script>}{}gis;  #remove scripts
	#$content=~ s{<html>}{}gis;
	#$content=~ s{</html>}{}gis;
	#$content=~ s{<body.*?>}{}gis;
	#$content=~ s{</body>}{}gis;
	
	#remove all remaining html tags (including comments)
	$content=~ s/\<.*?\>/ /gs;
	
	#2.4 make into one long string
	$content=~ s{[\t\r\n ]+}{ }gs;
	
	$content=~ s{\s+}{ }gs;  #collapse whitespace

	print "\nCONTENT: $content\n";
	
	#3.1 run through keyphrase extractor to get X keyphrases
	&ExtractKeyphrasesFromText($keywords_hash_ref, $content, $stopwords_array_ref, $max,$min_length, $phrase_length);
}

sub ExtractKeyphrasesFromText
{
	####################################
	#	PARAMETERS:
	#		keywords_hash_ref: hash reference for keyphrases to be returned in as
	#		                   $keywords_hash_ref->{"$keyphrase"}{"count"}= $count
	#		                   $keywords_hash_ref->{"$keyphrase"}{"rank"}= $rank
	#		                   Calling script example
	#                        my %kp;
	#		                     &Keyphrase::ExtractKeyphrasesFromText(\%kp, ...)
	#		                     foreach my $keyphrase (keys %kp)
	#		                     {
	#		                       my $count=$keywords_hash{"$keyphrase"}{"count"};
	#		                       my $rank=$keywords_hash{"$keyphrase"}{"rank"};
	#		                     }
	#		string: string to extract keyphrases from
	#		stopwords_array_ref: array reference that holds the array of stopwords
	#		max: maximum number of keyphrases to return
	#		min_length: minimum keyphrase length (in characters)
	#		phrase_length: number of words per phrase (ex. 3 will give 3-word keyphrases)
	#		print: prints out an HTML table of the keyphrases
	#	
	# RULES:
	#   words:
	#     The string that is given is treated as one long string of words, rather
	#     than a string of sentences.
	#     This means that if "wordX wordY. WordZ" appears more than once in your
	#     string, then "wordX wordY wordZ" will be concidered a keyphrase.
	#     Any character that is not a letter, number, or hyphen (-) is
	#     considered to be a word separator.
	#     
	#   stopwords:
	#     A phrase is not considered a keyphrase if it starts or ends with a
	#     stopword. As an example, if your string was "car sales in america"
	#     and you wanted 3-word keyphrases and "in" was one of your stopwords,
	#     then "car sales in" would NOT be a keyphrase, but "sales in america"
	#     would be.
	#   
	#   minimum occurance:
	#     In order for a phrase to be considered a keyphrase, it must occur
	#     at least twice (this value might be increase in the future).
	#     
	#   hyphenated words:
	#     Hyphenated words are treated as single words as long as the whole
	#     thing appears on a single line (no line break in it).
	#   
	#   normalization:
	#     - "'s" is removed from the ends of all words
	#     - All HTML entities (such as &quot; and &#1202;) are removed.
	#     - "i.e." and  "e.g." are removed.
	#     - All words ending in "-" (dash) are removed.
	#     - After the phrase count has been taken, if both the singular and
	#       plural phrase appears, they are combined into just the singular.
	#       Plural is defined here as if phraseX exists and so does
	#       phraseX plus "s" (or if phraseX ends in "y", then replace "y"
	#       with "ies", instead of checking for "ys").
	#       More simple put:
	#         **** and ****s get combined to ****
	#         ***y and ***ies get combined to ***y
	#       Keep in mind it does this for phrases, not words, so in the above
	#       examples, **** is the phrase, not any single word.
	#     - All words ending in a hyphen are thrown out.
	#     - Any character that is not a letter, number, or hyphen (-) is
	#       considered to be a word separator.
	#       
	#   rank:
	#     Currently there is no ranking other than a reverse sort by count.
	#     This will become more sophisticated as we add in weighting algorithms.
	#   
	####################################
	
	my ($keywords_hash_ref, $string, $stopwords_array_ref, $max, $min_length, $phrase_length, $print)= @_;
	$print=0 if(not defined $print or $print eq '');
	$string= lc $string;
	
	$string=~ s{[\t\r\n\0 ]+}{ }g;
	$string=~ s/ [-&] / /g;
	$string=~ s/e\.g\./ /g;
	$string=~ s/i\.e\./ /g;
	#$string=~ s{<[A-Za-z0-9/]+>}{ }g;  #remove html tags
	$string=~ s{&[A-Za-z0-9#]+;}{ }g;  #remove html entities
	$string=~ s{[^A-Za-z\-\'&]}{ }g;
	#$string=~ s{ +}{ }g; #collapse multiple spaces
	$string=~ s{-+}{-}g; #collapse multiple dashes
	$string=~ s{\s+}{ }gs;  #collapse all whitespace into single spaces
	
	#normalize words
	my @words_temp= split (/ /, $string);
	my @words;
	foreach my $word (@words_temp)
	{
		#remove "'s" and "n't" and ending in non-alphanumeric
		$word=~ s/'s$//;
		#####$word=~ s/n't$//;  #don't do this because, for example, "can't" -> "ca"
		$word=~ s/[^A-Za-z0-9\-]$//;
		if($word !~ m/-$/)  #don't add words ending with "-"
		{
				push (@words, $word);
		}
	}
	
	my @phrases;
	my $word_count= scalar @words;
	my $word_index= 0;
	while($word_index < $word_count-$phrase_length)
	{
		### read $phrase_length words ###
		my $phrase= '';
		my $cursor= 0;
		while($cursor<$phrase_length)
		{
			$phrase.= ' ' if ($cursor > 0);
			$phrase.= $words[$word_index+$cursor];
			$cursor++;
		}
		######
		
		if(length $phrase >= $min_length)
		{
			push (@phrases, $phrase);
		}
		
		$word_index++;
	}
	
	@words= @phrases;
	
	#get unique list of words
  my %clean_hash = ();
	@clean_hash{@words} = ();
	delete $clean_hash{''};
	
	#get counts
	foreach my $word (@words)
	{
		if((not defined $clean_hash{"$word"}) or ($clean_hash{"$word"} eq ''))
		{
			$clean_hash{"$word"}= 0;
		}
		$clean_hash{"$word"}++;
	}
	
	#remove stopwords
	if($phrase_length>1) #mulitple word phrases
	{
		#remove phrases that start or end if a stopword
		#example: "used cars in ohio" would used
		# "used cars in" and "cars in ohio" as 3 word phrases.
		# "used cars in" would be removed since it ends with "in"
		foreach my $stopword (@$stopwords_array_ref)
		{
			my @removes= grep { $_=~ m/ ${stopword}$/ or $_=~ m/^${stopword} / } keys %clean_hash;
			delete @clean_hash{@removes};
		}
	}
	else  #single word phrases
	{
		delete @clean_hash{@$stopwords_array_ref};
	}
	
	@words= keys %clean_hash;
	
	#condense singular and plural forms (prefer singular form)
	foreach my $word (@words)
	{
		if(defined $clean_hash{"$word"} and $clean_hash{"$word"} > 0 and $word!~m{s$})
		{
			my $plural_word;
			$plural_word= $word.'s';
			$plural_word=~ s{ys$}{ies}; #if ends in "y" plural needs to end in "ies", not "ys"
			
			if(defined $clean_hash{"$plural_word"} and $clean_hash{"$plural_word"} > 0)
			{
				$clean_hash{"$word"}+= $clean_hash{"$plural_word"};
				delete $clean_hash{"$plural_word"};
			}
		}
	}
	
	#reverse sort by count/frequency
	@words = reverse sort {$clean_hash{"$a"} <=> $clean_hash{"$b"}} keys %clean_hash;
	
	#trucate list to top $max phrases
	if(defined $max and $max>0 and scalar @words > $max)
	{
		@words= splice (@words, 0, $max);
	}
	
	if($print)
	{
		print qq(
			<br/>
			<table border="1">
				<tr>
					<th colspan="3">$phrase_length-WORD KEYPHRASE COUNTS</td>
				</tr>
				<tr>
					<th>rank</th>
					<th>count</th>
					<th>keyphrase</th>
				</tr>
		);
	}
	
	#assign  rank and count to keywords_hash_ref that is passed in
	my $rank=1;
	foreach my $word (@words)
	{
		if($print)
		{
			print qq|\n<tr|;
			print qq| style="color:#999999"| if($clean_hash{"$word"}<=1);
			print qq|><td>$rank</td><td>$clean_hash{"$word"}</td><td>$word</td></tr>|;
		}
		
		#only add if occurs more than once
		if($clean_hash{"$word"} >= 2)
		{
			$keywords_hash_ref->{"$word"}{"count"}= $clean_hash{"$word"};
			$keywords_hash_ref->{"$word"}{"rank"}= $rank;
		}
		
		$rank++;
	}
	print "</table>" if $print;
	
	return;
}

sub ExtractKeyphrasesAlgo2
{
	####################################
	#	PARAMETERS:
	#		keywords_hash_ref: hash reference for keyphrases to be returned in as
	#		                   $keywords_hash_ref->{"$keyphrase"}{"count"}= $count
	#		                   $keywords_hash_ref->{"$keyphrase"}{"rank"}= $rank
	#		                   Calling script example
	#                        my %kp;
	#		                     &Keyphrase::ExtractKeyphrasesFromText(\%kp, ...)
	#		                     foreach my $keyphrase (keys %kp)
	#		                     {
	#		                       my $count=$keywords_hash{"$keyphrase"}{"count"};
	#		                       my $rank=$keywords_hash{"$keyphrase"}{"rank"};
	#		                     }
	#		string: string to extract keyphrases from
	#		stopwords_array_ref: array reference that holds the array of stopwords
	#		max: maximum number of keyphrases to return
	#		min_length: minimum keyphrase length (in characters)
	#		phrase_length: number of words per phrase (ex. 3 will give 3-word keyphrases)
	#		print: prints out an HTML table of the keyphrases
	#	
	# RULES:
	#   words:
	#     The string that is given is treated as one long string of words, rather
	#     than a string of sentences.
	#     This means that if "wordX wordY. WordZ" appears more than once in your
	#     string, then "wordX wordY wordZ" will be concidered a keyphrase.
	#     Any character that is not a letter, number, or hyphen (-) is
	#     considered to be a word separator.
	#     
	#   stopwords:
	#     A phrase is not considered a keyphrase if it starts or ends with a
	#     stopword. As an example, if your string was "car sales in america"
	#     and you wanted 3-word keyphrases and "in" was one of your stopwords,
	#     then "car sales in" would NOT be a keyphrase, but "sales in america"
	#     would be.
	#   
	#   minimum occurance:
	#     In order for a phrase to be considered a keyphrase, it must occur
	#     at least twice (this value might be increase in the future).
	#     
	#   hyphenated words:
	#     Hyphenated words are treated as single words as long as the whole
	#     thing appears on a single line (no line break in it).
	#   
	#   normalization:
	#     - "'s" is removed from the ends of all words
	#     - All HTML entities (such as &quot; and &#1202;) are removed.
	#     - "i.e." and  "e.g." are removed.
	#     - All words ending in "-" (dash) are removed.
	#     - After the phrase count has been taken, if both the singular and
	#       plural phrase appears, they are combined into just the singular.
	#       Plural is defined here as if phraseX exists and so does
	#       phraseX plus "s" (or if phraseX ends in "y", then replace "y"
	#       with "ies", instead of checking for "ys").
	#       More simple put:
	#         **** and ****s get combined to ****
	#         ***y and ***ies get combined to ***y
	#       Keep in mind it does this for phrases, not words, so in the above
	#       examples, **** is the phrase, not any single word.
	#     - All words ending in a hyphen are thrown out.
	#     - Any character that is not a letter, number, or hyphen (-) is
	#       considered to be a word separator.
	#       
	#   rank:
	#     Currently there is no ranking other than a reverse sort by count.
	#     This will become more sophisticated as we add in weighting algorithms.
	#   
	####################################
	
	my ($keywords_hash_ref, $string, $title, $stopwords_array_ref, $max, $min_length, $phrase_length, $print)= @_;
	$print=0 if(not defined $print or $print eq '');
	
	&LimitDocumentSize(\$string, 25000);
	
	&CleanString(\$string);
	
	#&LimitDocumentSize(\$string);
	
	&CleanString(\$title);
	
	#normalize words
	my @words_temp= split (/\s+/, $string);
	my @words;
	foreach my $word (@words_temp)
	{
		#remove "'s" and "n't" and ending in non-alphanumeric
		$word=~ s/'s$//;
		#####$word=~ s/n't$//;  #don't do this because, for example, "can't" -> "ca"
		#$word=~ s/[^A-Za-z0-9\-]$//;  #don't need this since CleanString was already used
		if($word !~ m/-$/)  #don't add words ending with "-"
		{
			push (@words, $word);
		}
	}
	undef @words_temp;
	
	my @phrases;
	my $word_count= scalar @words;
	my $word_index= 0;
	while($word_index < $word_count-$phrase_length)
	{
		### read $phrase_length words ###
		my $phrase= '';
		my $cursor= 0;
		while($cursor<$phrase_length)
		{
			$phrase.= ' ' if ($cursor > 0);
			$phrase.= $words[$word_index+$cursor];
			$cursor++;
		}
		######
		
		if(length $phrase >= $min_length)
		{
			push (@phrases, $phrase);
		}
		
		$word_index++;
	}
	
	@words= @phrases;
	
	#get unique list of words
  my %clean_hash = ();
	@clean_hash{@words} = ();
	delete $clean_hash{''};
	
	#get counts
	foreach my $word (@words)
	{
		if((not defined $clean_hash{"$word"}) or ($clean_hash{"$word"} eq ''))
		{
			$clean_hash{"$word"}= 0;
		}
		$clean_hash{"$word"}++;
	}
	
	#remove stopwords
	if($phrase_length>1) #mulitple word phrases
	{
		#remove phrases that start or end if a stopword
		#example: "used cars in ohio" would used
		# "used cars in" and "cars in ohio" as 3 word phrases.
		# "used cars in" would be removed since it ends with "in"
		foreach my $stopword (@$stopwords_array_ref)
		{
			#remove phrases that start or end with a stopword
			my @removes= grep { $_=~ m/ ${stopword}$/ or $_=~ m/^${stopword} / } keys %clean_hash;
			delete @clean_hash{@removes};
			
			#remove phrases that have a stopword in the middle where the
			#first or last word is less than 4 chars and that word does
			#not appear in the title
			if($phrase_length >= 3)
			{
				my @might_removes= grep { $_=~ m/^\S{1,3} ${stopword} / } keys %clean_hash;
				@removes= ();
				
				foreach my $remove (@might_removes)
				{
					$remove=~ m/^(\S+) /;
					my $short_word= $1;
					if($title !~ m/\b$short_word\b/)
					{
						push @removes, $remove;
					}
				}
				
				delete @clean_hash{@removes};
				
				
				@might_removes= grep { $_=~ m/ ${stopword} \S{1,3}$/ } keys %clean_hash;
				@removes= ();
				
				foreach my $remove (@might_removes)
				{
					$remove=~ m/ (\S+)$/;
					my $short_word= $1;
					if($title !~ m/\b$short_word\b/)
					{
						push @removes, $remove;
					}
				}
				
				delete @clean_hash{@removes};
			}
		}
	}
	else  #single word phrases
	{
		delete @clean_hash{@$stopwords_array_ref};
	}
	
	@words= keys %clean_hash;
	
	#condense singular and plural forms (prefer singular form)
	foreach my $word (@words)
	{
		if(defined $clean_hash{"$word"} and $clean_hash{"$word"} > 0 and $word!~m{s$})
		{
			my $plural_word;
			$plural_word= $word.'s';
			$plural_word=~ s{ys$}{ies}; #if ends in "y" plural needs to end in "ies", not "ys"
			
			if(defined $clean_hash{"$plural_word"} and $clean_hash{"$plural_word"} > 0)
			{
				$clean_hash{"$word"}+= $clean_hash{"$plural_word"};
				delete $clean_hash{"$plural_word"};
			}
		}
	}
	
	if($print)
	{
		print qq(
			<br/>
			<table border="1">
				<tr>
					<th colspan="3">$phrase_length-WORD KEYPHRASE COUNTS</td>
				</tr>
				<tr>
					<th>score</th>
					<th>count</th>
					<th>keyphrase</th>
				</tr>
		);
	}
	
	#assign rank and count to keywords_hash_ref that is passed in
	
	#reverse sort by count/frequency
	#@words = reverse sort {$clean_hash{"$a"} <=> $clean_hash{"$b"}} keys %clean_hash;
	my %final_hash;
	foreach my $word (keys %clean_hash)
	{
		#only add if occurs more than once
		if($clean_hash{"$word"} >= 2)
		{
			$final_hash{"$word"}{"count"}= $clean_hash{"$word"};
			$final_hash{"$word"}{"score"}= $clean_hash{"$word"}*$phrase_length;
			if($title=~ m/\b$word\b/)
			{ #add very high weight to phrases that are in the title
				$final_hash{"$word"}{"score"}*= 10000;
			}
		}
	}
	
	undef %clean_hash;
	
	@words = reverse sort {$final_hash{"$a"}{'score'} <=> $final_hash{"$b"}{'score'}} keys %final_hash;
	
	#trucate list to top $max phrases
	if(defined $max and $max>0 and scalar @words > $max)
	{
		@words= splice (@words, 0, $max);
	}
	
	my $rank=1;
	foreach my $word (@words)
	{
		if($print)
		{
			print qq|\n<tr><td align="right">$final_hash{"$word"}{"score"}</td><td align="right">$final_hash{"$word"}{'count'}</td><td align="left">"$word"</td></tr>|;
		}
		
		$keywords_hash_ref->{"$word"}{"count"}= $final_hash{"$word"}{"count"};
		$keywords_hash_ref->{"$word"}{"rank"}= $rank;
		$keywords_hash_ref->{"$word"}{"score"}= $final_hash{"$word"}{"score"};
		$keywords_hash_ref->{"$word"}{"phrase"}= $word;
		
		$rank++;
	}
	
	print "</table>" if $print;
	
	return;
}

sub ExtractKeyphrasesAlgo5
{
	####################################
	#	PARAMETERS:
	#		keywords_hash_ref: hash reference for keyphrases to be returned in as
	#		                   $keywords_hash_ref->{"$keyphrase"}{"count"}= $count
	#		                   $keywords_hash_ref->{"$keyphrase"}{"rank"}= $rank
	#		                   Calling script example
	#                        my %kp;
	#		                     &Keyphrase::ExtractKeyphrasesFromText(\%kp, ...)
	#		                     foreach my $keyphrase (keys %kp)
	#		                     {
	#		                       my $count=$keywords_hash{"$keyphrase"}{"count"};
	#		                       my $rank=$keywords_hash{"$keyphrase"}{"rank"};
	#		                     }
	#		string: string to extract keyphrases from
	#		stopwords_array_ref: array reference that holds the array of stopwords
	#		max: maximum number of keyphrases to return
	#		min_length: minimum keyphrase length (in characters)
	#		phrase_length: number of words per phrase (ex. 3 will give 3-word keyphrases)
	#		print: prints out an HTML table of the keyphrases
	#	
	# RULES:
	#   words:
	#     The string that is given is treated as one long string of words, rather
	#     than a string of sentences.
	#     This means that if "wordX wordY. WordZ" appears more than once in your
	#     string, then "wordX wordY wordZ" will be concidered a keyphrase.
	#     Any character that is not a letter, number, or hyphen (-) is
	#     considered to be a word separator.
	#     
	#   stopwords:
	#     A phrase is not considered a keyphrase if it starts or ends with a
	#     stopword. As an example, if your string was "car sales in america"
	#     and you wanted 3-word keyphrases and "in" was one of your stopwords,
	#     then "car sales in" would NOT be a keyphrase, but "sales in america"
	#     would be.
	#   
	#   minimum occurance:
	#     In order for a phrase to be considered a keyphrase, it must occur
	#     at least twice (this value might be increase in the future).
	#     
	#   hyphenated words:
	#     Hyphenated words are treated as single words as long as the whole
	#     thing appears on a single line (no line break in it).
	#   
	#   normalization:
	#     - "'s" is removed from the ends of all words
	#     - All HTML entities (such as &quot; and &#1202;) are removed.
	#     - "i.e." and  "e.g." are removed.
	#     - All words ending in "-" (dash) are removed.
	#     - After the phrase count has been taken, if both the singular and
	#       plural phrase appears, they are combined into just the singular.
	#       Plural is defined here as if phraseX exists and so does
	#       phraseX plus "s" (or if phraseX ends in "y", then replace "y"
	#       with "ies", instead of checking for "ys").
	#       More simple put:
	#         **** and ****s get combined to ****
	#         ***y and ***ies get combined to ***y
	#       Keep in mind it does this for phrases, not words, so in the above
	#       examples, **** is the phrase, not any single word.
	#     - All words ending in a hyphen are thrown out.
	#     - Any character that is not a letter, number, or hyphen (-) is
	#       considered to be a word separator.
	#       
	#   rank:
	#     Currently there is no ranking other than a reverse sort by count.
	#     This will become more sophisticated as we add in weighting algorithms.
	#   
	####################################
	
	my ($keywords_hash_ref, $string, $title, $stopwords_array_ref, $max, $min_length, $phrase_length, $print, $limit_size)= @_;
	$print=0 if(not defined $print or $print eq '');
	$limit_size=1 if(not defined $limit_size);
	
	&LimitDocumentSize(\$string, 25000) if $limit_size;
	
	&CleanString5(\$string);
	&CleanString5(\$title);
	
	#normalize words
	#remove all 's (apostrophe s)
	my $apos_s= qr"'s\b";
	$title=~ s/$apos_s//g;
	$string=~ s/$apos_s//g;
	
	my $ecstopper= '&ecstopper&';
	my $ectitle= '&ectitle&';
	
	
	if($phrase_length>1)
	{
		#mark all stopwords
		foreach my $stopword (@$stopwords_array_ref)
		{
			#remove phrases that start or end with a stopword
			# -- AND --
			#remove phrases that have a stopword in the middle where the
			#first or last word is less than 4 chars and that word does
			#not appear in the title
			
			my $exp1= qr"\b${stopword}\b";
			$string=~ s/($exp1)/$ecstopper$1/g;
		}
		
		#mark all title words
		foreach my $tword (split(/ +/, $title))
		{
			my $exp1= qr"\b${tword}\b";
			$string=~ s/($exp1)/$1$ectitle/g;
		}
	}
	
	
	my @words= split (/\s+/, $string);
	my %clean_hash = ();
	
	my @phrases;
	my $word_count= scalar @words;
	my $word_index= 0;
	
	while($word_index < $word_count-$phrase_length)
	{
		### read $phrase_length words ###
		my $phrase= join(' ', @words[$word_index ... $word_index + $phrase_length - 1]);
		
		if($phrase_length>1)
		{
			my $exp1= qr" ${ecstopper}\S*?(?:$ectitle)?$";  #ends in a stopword
			my $exp2= qr"^${ecstopper}\S*?(?:$ectitle)? ";  #begins with a stopword
			my $exp3= qr"^\S{1,3}(?!$ectitle) ${ecstopper}\S*?(?:$ectitle)? ";
			my $exp4= qr" ${ecstopper}\S*?(?:$ectitle)? \S{1,3}(?!$ectitle)$";
			if(not ($phrase=~ m/$exp1/ or $phrase=~ m/$exp2/ or $phrase=~ m/$exp3/ or $phrase=~ m/$exp4/))
			{
				$phrase=~ s/$ecstopper//go;
				$phrase=~ s/$ectitle//go;
				$clean_hash{"$phrase"}++ if(length $phrase >= $min_length);
			}
		}
		else
		{
			if(length $phrase >= $min_length)
			{
				$clean_hash{"$phrase"}++;
			}
		}
		$word_index++;
	}
	delete $clean_hash{''};
	
	#remove stopwords
	if($phrase_length==1) #single word phrases
	{
		delete @clean_hash{@$stopwords_array_ref};
	}
	
	#@words= keys %clean_hash;
	
	#condense singular and plural forms (prefer singular form)
	foreach my $word (keys %clean_hash)
	{
		if($word!~m{s$})
		{
			my $plural_word;
			$plural_word= $word.'s';
			$plural_word=~ s{ys$}{ies}; #if ends in "y" plural needs to end in "ies", not "ys"
			
			if(defined $clean_hash{"$plural_word"})
			{
				$clean_hash{"$word"}+= $clean_hash{"$plural_word"};
				delete $clean_hash{"$plural_word"};
			}
		}
	}
	
	if($print)
	{
		print qq(
			<br/>
			<table border="1">
				<tr>
					<th colspan="3">$phrase_length-WORD KEYPHRASE COUNTS</td>
				</tr>
				<tr>
					<th>score</th>
					<th>count</th>
					<th>keyphrase</th>
				</tr>
		);
	}
	
	#assign rank and count to keywords_hash_ref that is passed in
	
	#reverse sort by count/frequency
	#@words = reverse sort {$clean_hash{"$a"} <=> $clean_hash{"$b"}} keys %clean_hash;
	my %final_hash;
	foreach my $word (keys %clean_hash)
	{
		#only add if occurs more than once
		if($clean_hash{"$word"} >= 2)
		{
			$final_hash{"$word"}{"count"}= $clean_hash{"$word"};
			$final_hash{"$word"}{"score"}= $clean_hash{"$word"}*$phrase_length;
			if($title=~ m/\b$word\b/)
			{ #add very high weight to phrases that are in the title
				$final_hash{"$word"}{"score"}*= 10000;
			}
		}
	}
	
	undef %clean_hash;
	
	@words = reverse sort {$final_hash{"$a"}{'score'} <=> $final_hash{"$b"}{'score'}} keys %final_hash;
	
	#trucate list to top $max phrases
	if(defined $max and $max>0 and scalar @words > $max)
	{
		@words= splice (@words, 0, $max);
	}
	
	my $rank=1;
	foreach my $word (@words)
	{
		if($print)
		{
			print qq|\n<tr><td align="right">$final_hash{"$word"}{"score"}</td><td align="right">$final_hash{"$word"}{'count'}</td><td align="left">"$word"</td></tr>|;
		}

		$word=~ s/_/-/g;
		
		$keywords_hash_ref->{"$word"}{"count"}= $final_hash{"$word"}{"count"};
		$keywords_hash_ref->{"$word"}{"rank"}= $rank;
		$keywords_hash_ref->{"$word"}{"score"}= $final_hash{"$word"}{"score"};
		$keywords_hash_ref->{"$word"}{"phrase"}= $word;
		
		$rank++;
	}
	
	print "</table>" if $print;
	
	return;
}

sub CleanString5
{
	my $string_ref= shift;
	
	$$string_ref= lc $$string_ref;
	
	#$$string_ref=~ s{[\t\r\n\0 ]+}{ }g;
	$$string_ref=~ s{\s+}{ }gs;  #collapse all whitespace into single spaces
	
	#$$string_ref=~ s/ [-&] / /g;
	$$string_ref=~ s/e\.g\./ /g;
	$$string_ref=~ s/i\.e\./ /g;
	$$string_ref=~ s{<.+?>}{ }g;  #remove html tags
	$$string_ref=~ s{&[A-Za-z0-9#]+;}{ }g;  #remove html entities
	$$string_ref=~ s{[^A-Za-z\-]}{ }g;
	$$string_ref=~ s/-{2,}/ /g; #concider multiple dashes a word separator
	$$string_ref=~ s/-/_/g; #concider multiple dashes a word separator
	$$string_ref=~ s{ +}{ }g;  #collapse all whitespace into single spaces
	$$string_ref=~ s{^ }{}g;
	$$string_ref=~ s{ $}{}g; 
	
	return;
}


sub CleanString
{
	my $string_ref= shift;
	
	$$string_ref= lc $$string_ref;
	
	#$$string_ref=~ s{[\t\r\n\0 ]+}{ }g;
	$$string_ref=~ s{\s+}{ }gs;  #collapse all whitespace into single spaces
	
	#$$string_ref=~ s/ [-&] / /g;
	$$string_ref=~ s/e\.g\./ /g;
	$$string_ref=~ s/i\.e\./ /g;
	$$string_ref=~ s{<.+?>}{ }g;  #remove html tags
	$$string_ref=~ s{&[A-Za-z0-9#]+;}{ }g;  #remove html entities
	$$string_ref=~ s{[^A-Za-z\-\'&]}{ }g;
	$$string_ref=~ s/-{2,}/ /g; #concider multiple dashes a word separator
	$$string_ref=~ s{\s+}{ }g;  #collapse all whitespace into single spaces
	
	return;
}


sub LimitDocumentSize
{
	my $string_ref= shift;
	my $size= shift;
	
	$size= 10000 if not defined $size;
	
	$$string_ref= substr($$string_ref,0,$size);
}


1;
