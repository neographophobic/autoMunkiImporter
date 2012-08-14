# perlplist.pl by James Reynolds
# www.magnusviri.com/computers/perlplist.html

################################################################################
# Portions Copyright (c) 2011 James Reynolds
# Other Portions Copyright (c) 2011 University of Utah Student Computing Labs.
# All Rights Reserved.
#
# Permission to use, copy, modify, and distribute this software and
# its documentation for any purpose and without fee is hereby granted,
# provided that the above copyright notice appears in all copies and
# that both that copyright notice and this permission notice appear
# in supporting documentation, and that the name of The University
# of Utah (or James Reynolds) not be used in advertising or publicity 
# pertaining to distribution of the software without specific, written 
# prior permission. This software is supplied as is without expressed or
# implied warranties of any kind.
################################################################################
#
# Version 8.3.14
# - Added -ai token for setPlistObjectForce, which inserts an object at an array 
#   index instead or replacing the object.
#
# Version 8.3.13
# - Added hexToBase64 and base64toHex, which now allow printing NSData objects.
# - perlValue can now convert NSData, NSArray, and NSDictionary objects to perl
#   versions.  It returns a hex string for NSData.
# - Added cocoaDataFromHex( $hex ) and cocoaDataFromBase64( $base64), which take
#   a hex or base64 string and make an NSData object with it.
#
# Version 8.3.12
# - Added instructions.
# - Updated objectType for 10.7.  
# - Enabled "defaultsFromString" to return results if it is array (system_profiler
#   returns arrays).
# - Added pathsThatMatchPartialPathWithGrep and pathsThatMatchPartialPathLooper.
# - Removed getDictInArrayWithKeyValue since pathsThatMatchPartialPathWithGrep does it
#   better.
#
# Version 8.3.11
# - Added objectType, numberType, and switched all "substr(ref())" calls to use objectType.
# - Added combineObjects subroutine, the 'combine' output option and modified plistDiff,
#   diffLoopThroughNSArrays, diffLoopThroughNSDicts, and dealWithResult to handle combines.
#
# Version 8.3.10
# - Made loadDefaults and loadDefaultsArray more robust
# - Added prettyPrintObject, printLoopThroughNSDicts, printLoopThroughNSArrays
#
# Version 8.3.9
# - Added defaultsFromString
#
# Version 8.3.8
# - Added loadDefaultsArray and getDictInArrayWithKeyValue
#
# Version 8.3.7
# - Added some nifty plist compare subroutines (2009.08.29 day after 10.6 was released)
#
# Version 8.3.6
# - Changed syntax of setPlistObjectForce so that it requires -d or -a at start
# (rather than assume -d)
#
# Version 8.3.5
# - using File::Basename instead of calling shell's dirname command in saveDefaults
#
# Version 8.3.4
# - Changed syntax of setPlistObjectForce so that date is -t (instead of -d)
# and dict is -d (instead of -h)

###########################################################################
#
# Instructions last updated 2011, June 7th
#
#  expandFilePath( $filepath ); 
#    Expands ~/ to be the home folder
#   
#  defaultsFromString( $string ); 
#    Converts $string to an NSDictionary (string must be xml plist).  Example:
#      my $xml = `/usr/sbin/system_profiler -xml`; # returns an array
#      my $array = defaultsFromString( $xml );
#
#  loadDefaults( $filepath ); 
#    Loads the plist file $filepath and returns an NSMutableDictionary (or nil if there is an
#    error) 
#  
#  loadDefaultsArray( $filepath )
#    Loads the plist file $filepath and returns an NSMutableArray (or nil if there is an 
#    error).  Most plist files start with a dictionary, so this is rarely needed.
#  
#  saveDefaults( $cocoa_plist, $filepath )
#    Saves an NSArray or NSDictionary ($cocoa_plist) to a filepath ($filepath)
#  
#  getPlistObject( $object, @keysIndexes )
#    Digs into $object (can be either an NSArray or NSDictionary) and uses @keysIndexes as
#    either dictionary keys or array indexes and returns the last object or nil if an error
#
#  getValueFromPlist( $object )
#    Returns a UTF8 String from the object returned by getPlustObject. Useful to get a
#    string value from a plist.
#
#  pathsThatMatchPartialPathWithGrep( $dict, @keysIndexes );
#    This subroutine searches a plist file and returns paths to what it finds.  The idea is
#    that you know the basic path but you aren't sure what index of an array or what key in a
#    dictionary you need to search for so you search all of the array items or use a regex to
#    find the key.  Because multiple items can be found, this subroutine returns an array of
#    paths that match.  
#
#    This subroutine still expects paths to be in the correct nesting and order.  In other
#    words, you just can't tell it to search for all occurrences of regex in a plist file, you
#    have to specify each path component.
#
#    When searching arrays, you can tell it to use a specific index ("1"), a list of indexes
#    ("[0, 1, 4]"), or all indexes ("*").
#
#    Keys are searched using regex patterns.  If you want an exact key, you must put ^$ around
#    it.  Because it is a string, if you include $ at the end, you must either escape it or use
#    single quotes, so "^pattern\$" or '^pattern$'.
#
#    Values (strings, ints, etc) are also searched using regex patterns.
#
#    Here are examples.  The following obtains the plist.  To fully understand this example you
#    should run `system_profiler -xml` and look at it while looking at the code.
#
#      my $xml = `/usr/sbin/system_profiler -xml`;
#      my $array = defaultsFromString( $xml );
#
#    The following searches the first index, the first 2 indexes, and all indexes of the array for
#    a dictionary containing a "_dataType" key with the value '^SPHardwareDataType$', 'Hardware',
#    and 'H[adrw]*e'. They all work, this is just a demonstration of the syntax and
#    possibilities.
#
#      @hardware_paths = pathsThatMatchPartialPathWithGrep ( $array, 0, '^_dataType$', '^SPHardwareDataType$' );
#      @hardware_paths = pathsThatMatchPartialPathWithGrep ( $array, [0,1], '^_dataType$', 'Hardware' );
#      @hardware_paths = pathsThatMatchPartialPathWithGrep ( $array, '*', '^_dataType$', 'H[adrw]*e' );
#
#    The following gets the object so it can be worked with. It uses the first item of @hardware_paths 
#    (the "$hardware_paths[0]"). Then it gets the first path component (the "${...}[0]"), which
#    is going to be the index that the SPHardwareDataType is located.
#
#      if ( $#hardware_paths < 0 ) {
#        print "Could not find SPHardwareDataType\n";
#      } else {
#        $hardware_array = getPlistObject ( $array, ${$hardware_paths[0]}[0], "_items" );
#      }
#
#    Print it out if you want to make sure it worked.
#
#      if ( ! ( $hardware_array and $$hardware_array ) ) {
#        print "Could not find _items\n";
#      } else {
#        printObject($hardware_array);
#      }
#
#    Print out the serial number (it assumes there is only one result so it looks at the 0
#    index of $hardware_array).
#
#      print ( perlValue( getPlistObject( $hardware_array, 0, "serial_number" ) ) );
#
#    This searches all indexes with "*" for a key "_dataType" and a value "SPNetworkDataType".
#
#      @network_paths = pathsThatMatchPartialPathWithGrep ( $array, '*', '^_dataType$', "SPNetworkDataType" );
#      if ( $#network_paths < 0 ) {
#        print "Could not find SPNetworkDataType\n";
#      } else {
#        $network_array = getPlistObject ( $array, ${$network_paths[0]}[0], "_items" );
#      }
#
#    This searches the $network_array from above to find all items with the key "Ethernet" and
#    the value "Mac Address".
#
#      @interfaces = pathsThatMatchPartialPathWithGrep( $network_array, '*', '^Ethernet$', '^MAC Address$' );
#
#    If you are feeling cowboy you can do all of the above in 1 step, but you might get 
#    unexpected results because system_profiler spews out a lot of data and something besides
#    SPNetworkDataType might match (but it doesn't in this case).
#
#      @cowboy = pathsThatMatchPartialPathWithGrep( $array, '*', '_items', '*', '^Ethernet$', '^MAC Address$' );
#
#    This prints out all MAC addresses on a computer (including FireWire and Airport) and
#    uses the safer $interfaces results and so it searches $network_array not $array.
#
#      foreach my $interface_ref ( @interfaces ) {
#        print perlValue( getPlistObject( $network_array, $$interface_ref[0], "Ethernet", "MAC Address" ) );
#      }
#
# pathsThatMatchPartialPathLooper( $object, $keysIndexesRef, $path_so_far, $results )
#    Used by pathsThatMatchPartialPathWithGrep.
#
#  setPlistObjectForce( $plistContainer, $pathRef )
#    Digs into $plistContrainer and users $pathRef to create a complete path.  $pathRef is
#    a reference to an array, and the array is a list of token and value pairs.  The tokens
#    represent the type (-d dict, -a array, -t date, -i int, -f float, -b bool, -s string).
#    The value is either going to be a key (if the preceding token is -d), index (if the
#    preceding token is -a), or value (the other tokens).
#
#    This is useful to create an instant plist structure if $plistContainer is empty or to
#    blindly set a value knowing there will be no error.  The $pathRef array items are not
#    Cocoa objects, but Perl scalars.
#
#    The pathRef array is quick way to dig into multiple dictionaries and arrays.  The last
#    2 items in the array refer to the type and value that is to be set.  All pairs preceding
#    the last 2 are -d or -a tokens and keys or indexes and these are used to nest the
#    desired value.
#
#    Container types specified in the path are created if they are missing.  If a value is
#    encountered that does not match the expected type, it will be replaced with the type
#    specified.  If the specified array index is too high empty objects are added to the
#    array until the index is no longer out of bounds.  Force is very forceful.
#
#    Array index values can also be "add", "+", or "push" to just add the object at the end.
#    The array index value "add_if_missing" will only add the object if the object is
#    missing.
#
#  setPlistObject( $plistContainer, @keyesIndexesValue )
#    This is similar to setPlistObjectForce except that this does not use type tokens nor
#    does it check or replace anything.  It assumes that everything exists already and that
#    you are working with Cocoa objects, not Perl scalars. Use this if you know the path
#    exists and that the types will not change.  The last item of @keyesIndexesValue must be
#    a Cocoa object or it will be converted to an NSString.
#
#  removePlistObject( $plistContainer, @keyesIndexesValue )
#    Basically the same as setPlistObject except it removes the last item.
#
#  perlArrayFromNSArray( $cocoaArray, $convertAll )
#    Converts an NSArray to a perl array.  If $convertAll evaluates to true all values are
#    converted and all type information is lost.  Otherwise, only the arrays and hashes are
#    converted and type of non-containers types are kept (which means they will be Cocoa
#    objects).
#
#  perlHashFromNSDict( $cocoaDict, $convertAll )
#    Same as perlArrayFromNSArray except it converts an NSDictionary to a perl hash.
#
#  cocoaDictFromPerlHash( %hash )
#    Converts a Perl hash to an NSDictionary.  All Perl Scalars are converted to NSStrings.
#    Cocoa objects in the hash are preserved.
#
#  cocoaArrayFromPerlArray( @perlArray )
#    Converts a Perl array to an NSArray.  All Perl Scalars are converted to NSStrings.
#    Cocoa objects in the array are preserved.
#
#  cocoaInt( $number )
#    Converts a Perl Scalar to an NSNumber using numberWithLong.
#
#  cocoaBool( $number )
#    Converts a Perl Scalar to an NSNumber using numberWithBool.  Use 1 for TRUE and 0 for
#    FALSE.
#
#  cocoaFloat( $number )
#    Converts a Perl Scalar to an NSNumber using numberWithDouble.
#
#  cocoaDate( $number )
#    Converts a Perl Scalar to an NSDate using dateWithTimeIntervalSince1970.
#
#  cocoaDataFromHex( $hex )
#    Converts a Perl Scalar of a hex value of an NSData object rather hackishly, using NSPropertyListSerialization.
#
#  cocoaDataFromBase64( $base64 )
#    Converts a Perl Scalar of a base64 value of an NSData object rather hackishly, using NSPropertyListSerialization.
#
#  plistDiff( $plist1, $plist2, $diff_options )
#    Compares 2 plist containers similar to the command line `diff` command. $diff_options
#    is a hash ref of options. Example:
#
#      plistDiff( $plist1, $plist2,
#                 { 'output' => 'see below for values',
#                   'max_depth' => 'see below for values',
#                   'output_types' => 'see below for values',
#                 }
#               );
#
#    Valid values are:
#      output: 'print', 'return' it as an array listing the changes, or 'combine' the plists
#      max_depth: a number specifying how deep to dig.
#      output_types: What to pay attention to
#        < print stuff that is present in $plist1 and not in $plist2
#        > print stuff that is present in $plist2 and not in $plist1
#        ! print stuff that is present in both plists but is different
#        = print stuff that is present in both plists but is the same
#        ? print stuff that isn't compared because it is deeper than max_depth
#
#  diffLoopThroughNSArrays()
#  diffLoopThroughNSDicts()
#  dealWithResult()
#    All these are used by pldiff
#
#  numberType()
#  objectType()
#  containerTypeOrValue()
#    Utility stuff that I don't feel like explaining.  These were written using 10.6 as a
#    guide and have been minimally updated for 10.7.
#
#  combineObjects( $cocoaDict1, $cocoaDict2 )
#    Shortcut for plistDiff( $cocoaDict1, $cocoaDict2, { 'output' => 'combine' } );
#
#  printObject()
#    Prints an xml representation of a plist object.
# 
#  printLoopThroughNSArrays()
#  printLoopThroughNSDicts()
#  prettyPrintObject()
#
#  hexToBase64( $hex )
#    This converts from the hex string that perlValue returns for NSData objects to a base64
#    encoded string.  XML plist files show base64 encoded NSData objects so this method will
#    do that make the conversion.
#
#      hexToBase64( "516df57a3c5b7a595eecf69e44011e9f711630ba236c59ac9bb2ee440b1c8ab2" );
#      returns UW31ejxbelle7PaeRAEen3EWMLojbFmsm7LuRAscirI=
#
#  base64toHex( $base64 );
#    This converts from a base64 string to binary data then to a hex string.  This is the
#    opposite of hexToBase64 and I'm still not sure what it will be used for, but here it is.
#    
#      base64toHex( "UW31ejxbelle7PaeRAEen3EWMLojbFmsm7LuRAscirI=" );
#      returns 516df57a3c5b7a595eecf69e44011e9f711630ba236c59ac9bb2ee440b1c8ab2
#
#  perlValue()
#    Used by printObject and other things.  This converts NSStrings, NSNumbers, NSBooleans,
#    NSDate, and NSData objects to perl strings using the description method.  This 
#    subroutine cleans up the hex string returned by the NSData's description method so it is
#    nothing but hex values.  It also converts NSArray's and NSDictionary's to perl arrays and
#    hashes (it's just a short cut for perlArrayFromNSArray and perlHashFromNSDict).
#    
 

use File::Basename;
use MIME::Base64;

# remove my to debug this script from another one.
my $debug = 0 if ! defined $debug;
my $debug_tracing = 0;

##
# File operations
##

sub expandFilePath {
  my ( $file ) = ( @_ );
  return NSString->stringWithFormat_( $file )->stringByExpandingTildeInPath->cString;
}

sub defaultsFromString {
  my ( $string ) = ( @_ );
  print "sub defaultsFromString start line " . __LINE__ . "\n" if $debug and $debug_tracing;
  # The 4 used below is: NSUTF8StringEncoding, defined in NSString.h (I have no idea how to use the enum typedef through the bridge)
  my $nsstring = NSString->stringWithFormat_($string);
  my $data = $nsstring->dataUsingEncoding_(4);
  # The 2 used below is: NSPropertyListMutableContainersAndLeaves aka kCFPropertyListMutableContainersAndLeaves, defined in NSPropertyList.h and CFPropertyList.h
  my $format;
  my $error;
  my $plist = NSPropertyListSerialization->propertyListFromData_mutabilityOption_format_errorDescription_($data, 2, \$format, \$error);
  if ( $plist and $$plist ) {
    if ( $plist->isKindOfClass_( NSDictionary->class ) or $plist->isKindOfClass_( NSArray->class ) ) {
      return $plist;
    } else {
      print "ERROR perlplist.pl, defaultsFromString: Object type was not a dictionary or array.\n";
    }
  } else {
    print "ERROR perlplist.pl, defaultsFromString: Could not convert string to plist.\n";
  }
}

sub loadDefaults {
  my ( $file ) = ( @_ );
  print "sub loadDefaults start line " . __LINE__ . "\n" if $debug and $debug_tracing;
  if ( -e $file ) {
    my $dictonary = NSMutableDictionary->dictionaryWithContentsOfFile_( $file );
    if ( $dictonary and $$dictonary ) { 
      return $dictonary;
    }
  }
  return;
}

sub loadDefaultsArray {
  my ( $file ) = ( @_ );
  print "sub loadDefaultsArray start line " . __LINE__ . "\n" if $debug and $debug_tracing;
  if ( -e $file ) {
    my $array = NSMutableArray->arrayWithContentsOfFile_( $file );
    if ( $array and $$array ) { 
      return $array;
    }
  }
  return;
}

sub saveDefaults {
  my ( $dict, $file ) = ( @_ );
  print "sub saveDefaults start line " . __LINE__ . "\n" if $debug and $debug_tracing;
  if ( ( -f $file and -w $file ) or -w ( dirname "$file" ) ) {
    $dict->writeToFile_atomically_( $file, "0" );
    return 1;
  } else {
    return 0;
  }
}

##
# Read operations
##

sub getPlistObject {
  my ( $object, @keysIndexes ) = ( @_ );
  print "sub getPlistObject start line " . __LINE__ . "\n" if $debug and $debug_tracing;
  if ( @keysIndexes ) {
    foreach my $keyIndex ( @keysIndexes ) {
      if ( $object and $$object ) {
        if ( $object->isKindOfClass_( NSArray->class ) ) {
          my $count = $object->count;
          if ( $keyIndex < $count ) {
            $object = $object->objectAtIndex_( $keyIndex );
          } else {
            print STDERR "Tried to get an index that doesn't exist.  Count: $count\n";
            return;
          }
        } elsif ( $object->isKindOfClass_( NSDictionary->class ) ) {
          $object = $object->objectForKey_( $keyIndex );
        } else {
          print STDERR "Unknown type (not an array or a dictionary): $object\n";
          return;
        }
      } else {
        print STDERR "Got nil or other error for $keyIndex in (@keysIndexes).\n";
        return;
      }
    }
  }
  return $object;
}

# vvv Added by Adam vvv 
sub getValueFromPlist {
	# Helper function to return a value as a string from a plist
	my ( $object ) = ( @_ );
	return $object->description()->UTF8String();
}
# ^^^ Added by Adam ^^^

sub pathsThatMatchPartialPathWithGrep {
  my ( $object, @keysIndexes ) = ( @_ );
  print "sub pathsThatMatchPartialPathWithGrep start line " . __LINE__ . "\n" if $debug and $debug_tracing;
  my @results = ();
  my @path_so_far = ();
  my $current_search_object = $object;
  pathsThatMatchPartialPathLooper( $object, \@keysIndexes, \@path_so_far, \@results);
  return @results;
}

sub pathsThatMatchPartialPathLooper {
  my ( $object, $keysIndexesRef, $path_so_far, $results ) = ( @_ );
  print "sub pathsThatMatchPartialPathLooper start line " . __LINE__ . "\n" if $debug and $debug_tracing;
  print "start $object, @$keysIndexesRef, @$path_so_far\n" if $debug;

  my @keysIndexes = @$keysIndexesRef;
  if ( $object and $$object ) {
    if ( $object->isKindOfClass_( NSArray->class ) ) {
      my $search_tokens = shift @keysIndexes;
      my @search_list;
      if ( $search_tokens eq '*' ) {
        @search_list = (0..$object->count-1);
      } elsif ( ref ( $search_tokens ) eq "ARRAY" ) {
        @search_list = ( @$search_tokens );
      } else {
        @search_list = ( $search_tokens );
      }
      foreach my $search_index ( @search_list ) {
        print "searching index: $search_index\n" if $debug;
        my $matched_object = $object->objectAtIndex_( $search_index );
        if ( $matched_object and $$matched_object ) {
          if ( $#keysIndexes >= 0 ) {
            push @$path_so_far, $search_index;
            pathsThatMatchPartialPathLooper( $matched_object, \@keysIndexes, $path_so_far, $results );
            pop @$path_so_far;
          } else {
            print "match @$path_so_far, $search_index\n" if $debug;
            push @$results, [@$path_so_far, $search_index];
          }
        }
      }
    } elsif ( $object->isKindOfClass_( NSDictionary->class ) ) {
      my $enumerator = $object->keyEnumerator();
      my $grep_pattern = shift @keysIndexes;
      while ( $keyCocoa = $enumerator->nextObject() and $$keyCocoa ) {
        # compare
        my $key = perlValue($keyCocoa);
        #print "grep_pattern $grep_pattern, key $key\n";
        if ( $grep_pattern ne "" and $key =~ /$grep_pattern/ ) {
          if ( $#keysIndexes >= 0 ) {
            push @$path_so_far, $key;
            pathsThatMatchPartialPathLooper( $object->objectForKey_($keyCocoa), \@keysIndexes, $path_so_far, $results );
            pop @$path_so_far;
          } else {
            print "match @$path_so_far, $key\n" if $debug;
            push @$results, [@$path_so_far, $key];
          }
        }
      }
    } else {
      my $grep_pattern = shift @keysIndexes;
      my $string = perlValue($object);
      if ( $grep_pattern ne "" and $string =~ /$grep_pattern/ ) {
          if ( $#keysIndexes >= 0 ) {
            print STDERR "There are more keys/indexes but I just searched a non container type...";
          } else {
            print "match @$path_so_far, $string\n" if $debug;
            push @$results, [@$path_so_far, $string];
          }
      }
    }
  } else {
    print STDERR "Trying to search a container that is nil.\n";
    return;
  }
}

##
# Set operations
##

sub setPlistObjectForce {
  my ( $plistContainer, $pathRef ) = ( @_ );
  print "sub setPlistObjectForce start line " . __LINE__ . "\n" if $debug and $debug_tracing;

  my $perlplist_dict_token = '-d';
  my $perlplist_array_token = '-a';
  my $perlplist_array_insert_token = '-ai';
  my $perlplist_date_token = '-t';
  my $perlplist_int_token = '-i';
  my $perlplist_float_token = '-f';
  my $perlplist_bool_token = '-b';
  my $perlplist_string_token = '-s';
  my $perlplist_hex_token = '-h';
  my $perlplist_base64_token = '-e';

  my @path = @$pathRef;
  my $objectToSet = pop ( @path );

  my @keyesIndexesSoFar = ();

  my $last_container_type = shift ( @path );
  my $parentContainer = $plistContainer;

  for ( $ii = 0; $ii <= $#path; $ii+=2 ) {
    
    my $value_token = $path[$ii];
    my $data_type_token = $path[$ii+1];
    push @keyesIndexesSoFar, $value_token;

    print "keyesIndexesSoFar @keyesIndexesSoFar\n" if $debug;

    # find/create missing container
    my $do_I_exist = getPlistObject( $plistContainer, @keyesIndexesSoFar );
    my $make_change = 0;

    if ( ! $$do_I_exist ) {
      $make_change = 1;
      print "Adding: @keyesIndexesSoFar (value type to be added: $data_type_token).\n";
    } else {
      if ( $data_type_token eq $perlplist_dict_token ) {
        if ( ! $do_I_exist->isKindOfClass_( NSDictionary->class ) ) {
          $make_change = 1;
          print "Should be dictionary but isn't: @keyesIndexesSoFar\n";
        } else {
          $parentContainer = $do_I_exist;
        }
      } elsif ( $data_type_token eq $perlplist_array_token or $data_type_token eq $perlplist_array_insert_token ) {
        if ( ! $do_I_exist->isKindOfClass_( NSArray->class ) ) {
          $make_change = 1;
          print "Should be array but isn't: @keyesIndexesSoFar\n";
        } else {
          $parentContainer = $do_I_exist;
        }
      } else {
        $make_change = 1;
      }
    }

    if ( $make_change ) {

      my $addMe;
      if ( $data_type_token eq $perlplist_dict_token ) {
        $addMe = cocoaDictFromPerlHash( ( ) );
      } elsif ( $data_type_token eq $perlplist_array_token or $data_type_token eq $perlplist_array_insert_token ) {
        $addMe = cocoaArrayFromPerlArray( ( ) );
      } elsif ( $data_type_token eq $perlplist_date_token ) {
        $addMe = cocoaDate( $objectToSet );
      } elsif ( $data_type_token eq $perlplist_int_token ) {
        $addMe = cocoaInt( $objectToSet );
      } elsif ( $data_type_token eq $perlplist_float_token ) {
        $addMe = cocoaFloat( $objectToSet );
      } elsif ( $data_type_token eq $perlplist_bool_token ) {
        $addMe = cocoaBool( $objectToSet );
      } elsif ( $data_type_token eq $perlplist_hex_token ) {
        $addMe =  cocoaDataFromHex( $objectToSet );
      } elsif ( $data_type_token eq $perlplist_base64_token ) {
        $addMe =  cocoaDataFromBase64( $objectToSet );
      } elsif ( $data_type_token eq $perlplist_string_token ) {
        $addMe =  $objectToSet;
      } else {
        print "ERROR perlplist.pl, Unknown token type! $data_type_token\n";
      }

      if ( $last_container_type eq $perlplist_array_token or $last_container_type eq $perlplist_array_insert_token ) {
        if ( $parentContainer->isKindOfClass_( NSArray->class ) ) {
          if ( $value_token eq "add" or $value_token eq "+" or $value_token eq "push" ) {
            $parentContainer->addObject_( $addMe );
          } elsif ( $value_token eq "add_if_missing" ) {

            $present = $parentContainer->containsObject_( $addMe );
            
            if ( ! $present ) {
              $parentContainer->addObject_( $addMe );
            }
          	
          } else {
            while ( $value_token >= $parentContainer->count ) {
              $parentContainer->addObject_( "" );
            }

            if ( $last_container_type eq $perlplist_array_insert_token ) {
              $parentContainer->insertObject_atIndex_( $addMe, $value_token );
            } else {
              $parentContainer->replaceObjectAtIndex_withObject_( $value_token, $addMe );
            }

          }
        } else {
          print STDERR "Tried to add array index to non-array container, stopping.\n";
          return;
        }
      } elsif ( $last_container_type eq $perlplist_dict_token ) {
        if ( $parentContainer->isKindOfClass_( NSDictionary->class ) ) {
          
          $parentContainer->setObject_forKey_( $addMe, $value_token );

        } else {
          print STDERR "Tried to add dictionary key-value pair to non-dictionary container, stopping.\n";
          return;
        }
      }
      $parentContainer = $addMe;
    }
    $last_container_type = $data_type_token;
  }
}

sub setPlistObject {
  my ( $plistContainer, @keyesIndexesValue ) = ( @_ );
  print "sub setPlistObject start line " . __LINE__ . "\n" if $debug and $debug_tracing;
  my $objectToSet = pop ( @keyesIndexesValue );
  my $keyIndex = pop ( @keyesIndexesValue );
  my $parentContainer = getPlistObject ( $plistContainer, @keyesIndexesValue );
  if ( $parentContainer and $$parentContainer ) {
    if ( $parentContainer->isKindOfClass_( NSArray->class ) ) {
      if ( $keyIndex > $parentContainer->count -1 ) {
        $parentContainer->addObject_( $objectToSet );
      } else {
        $parentContainer->replaceObjectAtIndex_withObject_( $keyIndex, $objectToSet );
      }
    } elsif ( $parentContainer->isKindOfClass_( NSDictionary->class ) ) {
      $parentContainer->setObject_forKey_( $objectToSet, $keyIndex );
    } else {
      print STDERR "Unknown parent container type.\n";
    }
  } else {
    print STDERR "Could not get value specified by @keyesIndexesValue.\n";
  }
}

sub removePlistObject {
  my ( $plistContainer, @keyesIndexesValue ) = ( @_ );
  print "sub removePlistObject start line " . __LINE__ . "\n" if $debug and $debug_tracing;
  my $keyIndex = pop ( @keyesIndexesValue );
  my $success = 0;
  my $parentContainer = getPlistObject ( $plistContainer, @keyesIndexesValue );
  if ( $parentContainer and $$parentContainer ) {
    if ( $parentContainer->isKindOfClass_( NSArray->class ) ) {
      if ( $keyIndex > $parentContainer->count -1 ) {
        print "removePlistObject: I don't think this should be possible\n";
        # don't think this should be possible
        #$parentContainer->addObject_( $objectToSet );
      } else {
        $parentContainer->removeObjectAtIndex_( $keyIndex );
        $success = 1;
      }
    } elsif ( $parentContainer->isKindOfClass_( NSDictionary->class ) ) {
      $parentContainer->removeObjectForKey_( $keyIndex );
      $success = 1;
    } else {
      print STDERR "Unknown parent container type.\n";
    }
  } else {
    print STDERR "Could not get value specified by @keyesIndexesValue.\n";
  }
  return $success;
}

##
# Convert operations
##

sub perlArrayFromNSArray {
  my ( $cocoaArray, $convertAll ) = ( @_ );
  print "sub perlArrayFromNSArray start line " . __LINE__ . "\n" if $debug and $debug_tracing;
  my @perlArray = ();
  my $enumerator = $cocoaArray->objectEnumerator();
  my $value;
  while ( $value = $enumerator->nextObject() and $$value ) {
    if ( objectType ( $value ) eq "NSCFArray" ) {
      my @newarray = perlArrayFromNSArray( $value, $convertAll );
      push (@perlArray, \@newarray);
    } elsif ( objectType ( $value ) eq "NSCFDictionary" ) {
      my %newhash = perlHashFromNSDict( $value, $convertAll );
      push (@perlArray, \%newhash);
    } else {
      push ( @perlArray, $convertAll ? perlValue( $value ) : $value );
    }
  }
  return @perlArray;
}

sub perlHashFromNSDict {
  my ( $cocoaDict, $convertAll ) = ( @_ );
  print "sub perlHashFromNSDict start line " . __LINE__ . "\n" if $debug and $debug_tracing;
  my %perlHash = ();
  my $enumerator = $cocoaDict->keyEnumerator();
  my $key;
  while ( $key = $enumerator->nextObject() and $$key ) {
    my $value = $cocoaDict->objectForKey_($key);
    if ( $value ) { # check to make sure an object was set
      if ( objectType ( $value ) eq "NSCFArray" ) {
        my @newarray = perlArrayFromNSArray( $value, $convertAll );
        $perlHash{ perlValue( $key ) } = \@newarray;
      } elsif ( objectType ( $value ) eq "NSCFDictionary" ) {
        my %newHash = perlHashFromNSDict( $value, $convertAll );
        $perlHash{ perlValue( $key ) } = \%newHash;
      } else {
        $perlHash{ perlValue( $key ) } = 
        $convertAll ? perlValue( $value ) : $value;
      }
    }
  }
  return %perlHash;
}

sub cocoaDictFromPerlHash {
  my ( %hash ) = ( @_ );
  print "sub cocoaDictFromPerlHash start line " . __LINE__ . "\n" if $debug and $debug_tracing;
  my $cocoaDict = NSMutableDictionary->dictionary();
  while ( my ( $key, $value ) = each( %hash ) ) {
    if ( defined $value ) {
      my $ref_value = ref ( $value );
      if ( ref ( $value ) eq "ARRAY" ) {
        $cocoaDict->setObject_forKey_( cocoaArrayFromPerlArray( @$value ), $key );
      } elsif ( ref ( $value ) eq "HASH" ) {
        $cocoaDict->setObject_forKey_( cocoaDictFromPerlHash( %$value ), $key );
      } elsif ( ref ( $value ) eq "SCALAR" ) {
        $cocoaDict->setObject_forKey_( $$value, $key );
      } elsif ( $ref_value =~ /NS/ ) {
        $cocoaDict->setObject_forKey_( $value, $key );
      } else {
        $cocoaDict->setObject_forKey_( "$value", $key );
      }
    } else {
      print STDERR "The value was not defined for $key!\n";
    }
  }
  return $cocoaDict;
}

sub cocoaArrayFromPerlArray {
  my ( @perlArray ) = ( @_ );
  print "sub cocoaArrayFromPerlArray start line " . __LINE__ . "\n" if $debug and $debug_tracing;
  my $cocoaArray = NSMutableArray->array();
  foreach my $value ( @perlArray ) {
    if ( defined $value ) {
      my $ref_value = ref ( $value );
      if ( ref ( $value ) eq "ARRAY" ) {
        $cocoaArray->addObject_( cocoaArrayFromPerlArray( @$value ) );
      } elsif ( ref ( $value ) eq "HASH" ) {
        $cocoaArray->addObject_( cocoaDictFromPerlHash( %$value ) );
      } elsif ( ref ( $value ) eq "SCALAR" ) {
        $cocoaArray->addObject_( $$value );
      } elsif ( $ref_value =~ /NS/ ) {
        $cocoaArray->addObject_( $value );
      } else {
        $cocoaArray->addObject_( "$value" );
      }
    } else {
      print STDERR "The value was not defined!\n";
    }
  }
  return $cocoaArray;
}

sub cocoaInt {
  return NSNumber->numberWithLong_( $_[0] );
}

sub cocoaBool {
  return NSNumber->numberWithBool_( $_[0] );
}

sub cocoaFloat {
  return NSNumber->numberWithDouble_( $_[0] );
}

sub cocoaDate {
  return NSDate->dateWithTimeIntervalSince1970_( $_[0] );
}

sub cocoaDataFromHex {
  my ( $hex ) = @_;
  print "sub cocoaDataFromHex start line " . __LINE__ . "\n" if $debug and $debug_tracing;
  if ( $hex !~ /^[0-9a-f]+$/ ) {
    print "ERROR perlplist.pl, cocoaDataFromHex, could not make an NSData from the following hex string: $hex (because it is not hex!)\n";
    return;
  }
  my $base64 = hexToBase64( $hex );
  return cocoaDataFromBase64( $base64 );
}

sub cocoaDataFromBase64 {
  my ( $base64 ) = @_;
  print "sub cocoaDataFromBase64 start line " . __LINE__ . "\n" if $debug and $debug_tracing;
  if ( $base64 !~ /^[0-9a-zA-Z\+\/]+\=*$/ ) {
    print "ERROR perlplist.pl, cocoaDataFromBase64, could not make an NSData from the following base64 string: $base64 (because it is not base64!)\n";
    return;
  }
  $base64 =~ s/[\n\r\t ]//g;
  $base64 = ("<plist version=\"1.0\"><data>$base64</data></plist>");
  my $nsstring = NSString->stringWithFormat_($base64);
  my $data = $nsstring->dataUsingEncoding_(4);
  # The 2 used below is: NSPropertyListMutableContainersAndLeaves aka kCFPropertyListMutableContainersAndLeaves, defined in NSPropertyList.h and CFPropertyList.h
  my $format;
  my $error;
  my $plist = NSPropertyListSerialization->propertyListFromData_mutabilityOption_format_errorDescription_($data, 2, \$format, \$error);
  if ( $plist and $$plist ) {
    if ( $plist->isKindOfClass_( NSData->class ) ) {
      return $plist;
    } else {
      print "ERROR perlplist.pl, cocoaDataFromBase64: Object type was not nsdata.\n";
    }
  } else {
    print "ERROR perlplist.pl, cocoaDataFromBase64: Could not convert string to nsdata plist.\n";
  }
}

##
# Diff options
##

sub plistDiff {
  my ( $value1, $value2, $diff_options ) = ( @_ );
  print "sub plistDiff start line " . __LINE__ . "\n" if $debug and $debug_tracing;
  $diff_options = {} if ! defined $diff_options;
  $$diff_options{'output'} = 'print' if ! defined $$diff_options{'output'}; # - what to do with result, 'print', 'return' it as an array, or 'combine' the plists
  $$diff_options{'max_depth'} = 0 if ! defined $$diff_options{'max_depth'}; # max depth -- set by user
  $$diff_options{'output_types'} = '<>!?' if ! defined $$diff_options{'output_types'};
  $$diff_options{'current_depth'} = 0 if ! defined $$diff_options{'current_depth'}; # current depth
  $$diff_options{'path'} = '' if ! defined $$diff_options{'path'}; # path

  my $path = $$diff_options{'path'};
  my $root = 0;
  if ( ! defined $$diff_options{'results'} ) {
    $root = 1;
    if ( defined $$diff_options{'output'} and $$diff_options{'output'} eq 'combine' ) {
      $$diff_options{'results'} = $value1;
    } else {
      $$diff_options{'results'} = [];
    }
  }
  if ( ref ( $value1 ) eq ref ( $value2 ) ) {
    if ( objectType ( $value1 ) eq "NSCFArray" ) {
      print "array\n" if $debug;
      if ( $$diff_options{'max_depth'} == 0 or $$diff_options{'current_depth'} < $$diff_options{'max_depth'} ) {
        $$diff_options{'current_depth'}++;
        diffLoopThroughNSArrays( $value1, $value2, $diff_options );
        $$diff_options{'current_depth'}--;
      } else {
        dealWithResult ( "?", "$path/ " . containerTypeOrValue( $value1 ), $diff_options );
      }
    } elsif ( objectType ( $value1 ) eq "NSCFDictionary" ) {
      print "dictionary\n" if $debug;
      if ( $$diff_options{'max_depth'} == 0 or $$diff_options{'current_depth'} < $$diff_options{'max_depth'} ) {
        $$diff_options{'current_depth'}++;
        diffLoopThroughNSDicts( $value1, $value2, $diff_options );
        $$diff_options{'current_depth'}--;
      } else {
        dealWithResult ( "?", "$path/ " . containerTypeOrValue( $value1 ), $diff_options );
      }
    } else {
      print "value\n" if $debug;
      if ( perlValue( $value1 ) eq perlValue( $value2 ) ) {
        dealWithResult ( "=", "$path/" . perlValue( $value1 ), $diff_options );
      } else {
        dealWithResult ( "!", "$path/ " . perlValue( $value1 ) . " != " . perlValue( $value2 ), $diff_options );
      }
    }
  } else {
    dealWithResult ( "!", "$path/ " . containerTypeOrValue( $value1 ) . " != " . containerTypeOrValue( $value2 ), $diff_options );
  }
  if ( $root ) {
    if ( $$diff_options{'output'} eq 'combine' ) {
      return $$diff_options{'results'};
    } elsif ( $$diff_options{'output'} eq 'return' ) {
      return @{$$diff_options{'results'}};
    }
  }
}

sub diffLoopThroughNSArrays {
  my ( $cocoaArray1, $cocoaArray2, $diff_options ) = ( @_ );
  print "sub diffLoopThroughNSArrays start line " . __LINE__ . "\n" if $debug and $debug_tracing;
  my $path = $$diff_options{'path'};
  my $enumerator1 = $cocoaArray1->objectEnumerator();
  my $value1;
  my $counter = 0;
  while ( $value1 = $enumerator1->nextObject() and $$value1 ) {
    if ( $counter < $cocoaArray2->count ) {
      $$diff_options{'path'} = "$path/[$counter]";
      print $$diff_options{'path'} ."\n" if $debug;
      plistDiff( $value1, $cocoaArray2->objectAtIndex_($counter), $diff_options );
    } else {
      dealWithResult ( "<", "$path/[$counter]/".perlValue($value1), $diff_options );
    }
    $counter++;
  }
  # Find missing
  for ( $ii = $counter; $ii < $cocoaArray2->count; $ii++ ) {
    my $value2 = $cocoaArray2->objectAtIndex_($ii);
    if ( $$diff_options{'output'} eq 'combine' ) {
      $cocoaArray1->addObject_( $value2 );
    } else {
      dealWithResult ( ">", "$path/[$ii]/".perlValue($value2), $diff_options );
    }
  }
}

sub diffLoopThroughNSDicts {
  my ( $cocoaDict1, $cocoaDict2, $diff_options ) = ( @_ );
  print "sub diffLoopThroughNSDicts start line " . __LINE__ . "\n" if $debug and $debug_tracing;
  my $path = $$diff_options{'path'};
  my $enumerator1 = $cocoaDict1->keyEnumerator();
  my $key1;
  my %found_keys = ();
  while ( $key1 = $enumerator1->nextObject() and $$key1 ) {
    my $value1 = $cocoaDict1->objectForKey_($key1);
    if ( $value1 ) { # check to make sure an object was set
      $found_keys{perlValue($key1)} = '1';
      my $value2 = $cocoaDict2->objectForKey_($key1);
      if ( $$value2) { # check to make sure an object was set
        $$diff_options{'path'} = "$path/{".perlValue($key1)."}";
        print $$diff_options{'path'} ."\n" if $debug;
        plistDiff( $value1, $value2, $diff_options );
      } else {
        dealWithResult ( "<", "$path/{".perlValue($key1)."}/".containerTypeOrValue($value1), $diff_options );
      }
    }
  }
  # Find missing keys
  my $enumerator2 = $cocoaDict2->keyEnumerator();
  my $key2;
  while ( $key2 = $enumerator2->nextObject() and $$key2 ) {
    my $value2 = $cocoaDict2->objectForKey_($key2);
    if ( $value2 ) { # check to make sure an object was set
      if ( ! $found_keys{perlValue($key2)} ) {
        if ( $$diff_options{'output'} eq 'combine' ) {
          $cocoaDict1->setObject_forKey_( $value2, $key2 );
        } else {
          dealWithResult ( ">", "$path/{".perlValue($key2)."}/".containerTypeOrValue($value2), $diff_options );
        }
      } 
    }
  }
}

sub dealWithResult {
  my ( $result, $path, $diff_options ) = @_;
  print "sub dealWithResult start line " . __LINE__ . "\n" if $debug and $debug_tracing;
  if ( index ( $$diff_options{'output_types'}, $result ) >= 0 ) {
    if ( $$diff_options{'output'} eq 'print' ) {
      print "$result $path\n";
    } elsif ( $$diff_options{'output'} eq 'return' ) {
      push @{$$diff_options{'results'}}, "$result $path";
    } elsif ( $$diff_options{'output'} eq 'combine' ) {
      if ( $result eq "<" ) {
      } elsif ( $result eq ">" ) {
        die "A combine for > should have been dealt with elsewhere.\n";
      } elsif ( $result eq "=" ) {
      } elsif ( $result eq "!" ) {
        die "Your plist files share keys but have different values $path.\n";
      } elsif ( $result eq "?" ) {
        die "Can't combine when using a max depth (shouldn't even be possible).\n";
      }
    } else {
      die "Error, the plistDiff subroutine needs an optional 'print', 'return', or 'combine' string: plistDiff(cocoaDict1, cocoaDict2, ['print'],3); # or use 'return', the number 3 refers to the max depth.";
    }
  }
}

sub numberType {
  my ( $value ) = @_;
  print "sub numberType start line " . __LINE__ . "\n" if $debug and $debug_tracing;
  my $type = $value->objCType();
  if ( $type eq 'i' or $type eq 'q' ) {
    return "integer";
  } elsif ( $type eq 'd' or $type eq 'f' ) {
    return "real";
  } else {
    die "Unknown number type $type (see http://developer.apple.com/library/mac/#documentation/cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtTypeEncodings.html)\n";
  }
}

sub objectType {
  my ( $value ) = @_;
  print "sub objectType start line " . __LINE__ . "\n" if $debug and $debug_tracing;
  if ( $value =~ /(__)?NS(CF)?Array/ ) {
    return "NSCFArray";
  } elsif ( $value =~ /(__)?NSCFDictionary/ ) {
    return "NSCFDictionary";
  } elsif ( $value =~ /(__)?NSCF(Constant)?String/ ) {
    return "NSCFString";
  } elsif ( $value =~ /(__)?NSCFBoolean/ ) {
    return "NSCFBoolean";
  } elsif ( $value =~ /(__)?NSCFNumber/ ) {
    return "NSCFNumber";
  } elsif ( $value =~ /(__)?NSCFDate/ ) {
    return "NSCFDate";
  # vvv Added by Adam vvv
  } elsif ( $value =~ /(__)?NSTaggedDate/ ) {
    return "NSCFDate";
  # ^^^ Added by Adam ^^^
  } elsif ( $value =~ /(__)?NSCFData/ or $value =~ /NSConcreteData/ ) {
    return "NSCFData";
  } else {
    die "Unknown Objective-C object type: ". ref ( $value ) . " value: $value";
  }
}

sub containerTypeOrValue {
  my ( $value ) = @_;
  print "sub containerTypeOrValue start line " . __LINE__ . "\n" if $debug and $debug_tracing;
  if ( objectType ( $value ) eq "NSCFArray" ) {
    return "NSCFArray";
  } elsif ( objectType ( $value ) eq "NSCFDictionary" ) {
    return "NSCFDictionary";
  } else {
    return perlValue($value);
  }
}

sub combineObjects {
  my ( $cocoaDict1, $cocoaDict2 ) = ( @_ );
  print "sub combineObjects start line " . __LINE__ . "\n" if $debug and $debug_tracing;
  return plistDiff( $cocoaDict1, $cocoaDict2, { 'output' => 'combine' } );
}

## Testing code:
#use Foundation;
#my %test1 = ( '1' => { 1=>{1=>2}, 2=>[1,2] }, );
#my %test2 = ( '1' => { 1=>{1=>2}, 2=>[1,2] }, );
#plistDiff ( cocoaDictFromPerlHash (%test1), cocoaDictFromPerlHash (%test2), {'output'=>'print','max_depth'=>3} );

##
# Print options
##

sub printLoopThroughNSArrays {
  my ( $cocoaArray1, $spacer ) = ( @_ );
  print "sub printLoopThroughNSArrays start line " . __LINE__ . "\n" if $debug and $debug_tracing;
  my $enumerator1 = $cocoaArray1->objectEnumerator();
  my $value1;
  my $total_text = "$spacer<array>\n";
  print $total_text;
  while ( $value1 = $enumerator1->nextObject() and $$value1 ) {
    $total_text .= prettyPrintObject( $value1, "$spacer\t" );
  }
  $total_text .= "$spacer</array>\n";
  print "$spacer</array>\n";
  return $total_text;
}

sub printLoopThroughNSDicts {
  my ( $cocoaDict1, $spacer ) = ( @_ );
  print "sub printLoopThroughNSDicts start line " . __LINE__ . "\n" if $debug and $debug_tracing;
  my $enumerator1 = $cocoaDict1->keyEnumerator();
  my $key1;
  my $total_text = "$spacer<dict>\n";
  print $total_text;
  while ( $key1 = $enumerator1->nextObject() and $$key1 ) {
    my $value1 = $cocoaDict1->objectForKey_($key1);
    my $key_text = "$spacer\t<key>".perlValue($key1)."</key>\n";
    print $key_text;
    $total_text .= $key_text;
    if ( $value1 ) { # check to make sure an object was set
      $total_text .= prettyPrintObject( $value1, "$spacer\t" );
    } else {
      print "This shouldn't have happened. (printLoopThroughNSDicts)";
    }
  }
  $total_text .= "$spacer</dict>\n";
  print "$spacer</dict>\n";
  return $total_text;
}

sub printObject {
  my ( $value ) = ( @_ );
  print "sub printObject start line " . __LINE__ . "\n" if $debug and $debug_tracing;
  print <<EOF;
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
EOF
  my $text = prettyPrintObject($value);
  print "</plist>\n";
  return $value->description->cString();
}

sub prettyPrintObject {
  my ( $value, $spacer ) = ( @_ );
  print "sub prettyPrintObject start line " . __LINE__ . "\n" if $debug and $debug_tracing;
  $spacer = '' if ! defined $spacer;
  my $total_text;
  if ( $$value and $value ) {
    my $text;
    if ( objectType ( $value ) eq "NSCFArray" ) {
      printLoopThroughNSArrays($value, $spacer );
      $text = "";
    } elsif ( objectType ( $value ) eq "NSCFDictionary" ) {
      printLoopThroughNSDicts($value, $spacer );
      $text = "";
    } elsif ( objectType ( $value ) eq "NSCFString" ) {
      $text = "$spacer<string>".perlValue($value)."</string>\n";
    } elsif ( objectType ( $value ) eq "NSCFBoolean" ) {
      $text = ( perlValue($value) ) ? "$spacer<true/>\n" : "$spacer<false/>\n";
    } elsif ( objectType ( $value ) eq "NSCFNumber" ) {
      my $numberType = numberType( $value );
      $text = "$spacer<$numberType>".perlValue($value)."</$numberType>\n";
    } elsif ( objectType ( $value ) eq "NSCFDate" ) {
      $text = "$spacer<date>".perlValue($value)."</date>\n";
    } elsif ( objectType ( $value ) eq "NSCFData" ) {
      my $base64 = perlValue($value);
      my @base64chars = split(//,$base64);
      $base64 = "";
      my $counter = 0;
      foreach $char ( @base64chars ) {
        if ( $counter % 36 == 0 ) {
          $base64 .= "\n$spacer$char";
        } else {
          $base64 .= $char;
        }
        $counter++;
      }
      $text = "$spacer<data>$base64\n$spacer</data>\n";
    } else {
      die "Unknown Objective-C object type: ". ref ( $value );
    }
    print $text;
    $total_text .= $text;
  } else {
    print "<!-- nil object -->\n";
  }
  return $total_text;
}

sub hexToBase64 {
  my ( $hex ) = @_;
  print "sub hexToBase64 start line " . __LINE__ . "\n" if $debug and $debug_tracing;
  $hex =~ s/[<> ]//g; # get rid of the < .... .... > that NSData's description returns.
  my $binary = pack( 'H*', $hex );
  my $baseb4 = encode_base64($binary,"");
  return $baseb4;
}

sub base64toHex {
  my ( $base64 ) = @_;
  print "sub base64toHex start line " . __LINE__ . "\n" if $debug and $debug_tracing;
  $base64 =~ s/[\n\r\t ]//g;
  my $binary = decode_base64($base64);
  my( $hex ) = unpack( 'H*', $binary );
  return $hex;
}

sub perlValue {
  my ( $object ) = @_;
  print "sub perlValue start line " . __LINE__ . "\n" if $debug and $debug_tracing;
  my $return_value;
  if ( objectType ( $object ) eq "NSCFArray" ) {
    $return_value = perlArrayFromNSArray( $object, 1 );
  } elsif ( objectType ( $object ) eq "NSCFDictionary" ) {
    $return_value = perlHashFromNSDict( $object, 1 );
  } elsif ( objectType ( $object ) eq "NSCFData" ) {
    my $hex = $object->description()->UTF8String();
    $return_value = hexToBase64($hex);
  } elsif ( objectType ( $object ) eq "NSCFDate" ) {
	$return_value = $object->timeIntervalSince1970(); # Unix timestamp
    # $return_value = $object->descriptionWithLocale_(NSLocale->currentLocale())->UTF8String(); # - Formatted to the local timezone
  } else {
    $return_value = $object->description()->UTF8String();
    $return_value =~ s/&/&amp;/g;
  }
  return $return_value;
}

1;
