/*
 * SetAppAffinity.m
 * SetAppAffinity
 * 
 * Created by Jim Dovey on 28/10/2009.
 * 
 * Copyright (c) 2009 Jim Dovey
 * All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 
 * Redistributions of source code must retain the above copyright notice,
 * this list of conditions and the following disclaimer.
 * 
 * Redistributions in binary form must reproduce the above copyright
 * notice, this list of conditions and the following disclaimer in the
 * documentation and/or other materials provided with the distribution.
 * 
 * Neither the name of the project's author nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
 * TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */

#import <Foundation/Foundation.h>
#import <AppKit/NSWorkspace.h>
#import <AppKit/NSImage.h>
#import <CoreServices/CoreServices.h>

#import <getopt.h>
#import <sysexits.h>
#import <sys/syslimits.h>

static const char *		_shortCommandLineArgs = "ha:b:";
static struct option	_longCommandLineArgs[] = {
	{ "help", no_argument, NULL, 'h' },
	{ "app-path", required_argument, NULL, 'a' },
	{ "bundle-id", required_argument, NULL, 'b' },
	{ NULL, 0, NULL, 0 }
};

static void usage(FILE *, int) __dead2;

static void usage( FILE * fp, int exitCode )
{
	const char * procName = [[[NSProcessInfo processInfo] processName] UTF8String];
	fprintf( fp,
			 "Usage:\n"
			 "  %s [-h | --help]					Display this list of options.\n",
			 "  %s [-a | --app-path] <file1> <file2> ...\n"
			 "     Set named files to open using application bundle at <app-path>.\n"
			 "  %s [-b | --bundle-id] <file1> <file2> ...\n"
			 "     Set named files to open using application with a given identifier.\n"
			 "\n"
			 "Files to modify may be specified either on the command line or via\n"
			 "standard input. If using standard input, the paths are expected to be\n"
			 "separated by newline characters.",
			 procName, procName, procName );
	fflush( fp );
	exit( exitCode );
}

static void RemoveUsroResource( NSURL * fileURL )
{
	FSRef fsRef;
	if ( CFURLGetFSRef((CFURLRef)fileURL, &fsRef) == FALSE )
	{
		fprintf( stderr, "Failed to access input file.\n" );
		exit( EX_OSERR );
	}
	
	ResFileRefNum refnum = FSOpenResFile( &fsRef, fsRdWrPerm );
	
	Handle oldUsro = Get1Resource( 'usro', 0 );
	if ( oldUsro != NULL )
		RemoveResource( oldUsro );	// this invalidates the handle
	
	CloseResFile( refnum );
}

static BOOL InstallUsroResource( NSURL * fileURL, NSURL * appURL )
{
	FSRef fileRef;
	if ( CFURLGetFSRef((CFURLRef)fileURL, &fileRef) == FALSE )
	{
		fprintf( stderr, "Failed to access input file.\n" );
		exit( EX_OSERR );
	}
	
	Handle newUsro = NewHandleClear( PATH_MAX + sizeof(UInt32) );
	char * bytes = (char *) *newUsro;	// a Handle is a ptr to a ptr
	
	const char * path = [[appURL path] UTF8String];
	UInt32 len = (UInt32) MIN(strlen(path), PATH_MAX);
	
	// copy the data in: 32-bit length followed by path (similar to a HFS string)
	memcpy( bytes, &len, sizeof(UInt32) );
	memcpy( (bytes+sizeof(UInt32)), path, len );
	
	ResFileRefNum refnum = FSOpenResFile( &fileRef, fsRdWrPerm );
	
	// add the resource to the file
	AddResource( newUsro, 'usro', 0, "\p" );	// last param is an empty Pascal string
	DisposeHandle( newUsro );					// release the handle memory
	
	BOOL result = (ResError() == noErr);
	
	CloseResFile( refnum );
	return ( result );
}

NSImage * GetAppFileIcon( NSURL * appURL, NSURL * fileURL, NSString * uti )
{
	NSBundle * appBundle = [NSBundle bundleWithURL: appURL];
	NSArray * docTypes = [[appBundle infoDictionary] objectForKey: @"CFBundleDocumentTypes"];
	NSString * extension = [fileURL pathExtension];
	NSString * iconName = nil;
	
	for ( NSDictionary * docType in docTypes )
	{
		if ( ([[docType objectForKey: @"LSItemContentTypes"] containsObject: uti]) ||
			 ([[docType objectForKey: @"CFBundleTypeExtensions"] containsObject: extension]) )
		{
			iconName = [docType objectForKey: @"CFBundleTypeIconFile"];
			break;
		}
	}
	
	if ( iconName == nil )
		return ( nil );
	
	return ( [[NSImage alloc] initWithContentsOfURL: [appBundle URLForImageResource: iconName]] );
}

int main (int argc, const char * argv[])
{
	NSURL * appURL = nil;
    
	int ch = 0;
	while ( (ch = getopt_long(argc, (char **)argv, _shortCommandLineArgs, _longCommandLineArgs, NULL)) != -1 )
	{
		switch ( ch )
		{
			default:
				usage( stderr, EX_USAGE );	// dead call
				break;
			
			case 'h':
				usage( stdout, EX_OK );	// dead call, exits app
				break;
				
			case 'a':
			{
				NSString * path = [NSString stringWithUTF8String: optarg];
				if ( [[NSFileManager defaultManager] fileExistsAtPath: [appURL path]] == NO )
				{
					fprintf( stderr, "Unable to locate application at path '%s'\n", optarg );
					fflush( stderr );
					exit( EX_DATAERR );
				}
				
				appURL = [NSURL fileURLWithPath: path];
				break;
			}
				
			case 'b':
			{
				appURL = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier: [NSString stringWithUTF8String: optarg]];
				if ( appURL == nil )
				{
					fprintf( stderr, "Unable to locate application with identifier '%s'\n", optarg );
					fflush( stderr );
					exit( EX_DATAERR );
				}
				break;
			}
		}
	}
	
	NSMutableArray * files = [NSMutableArray array];
	
	if ( optind < argc )
	{
		// build the list of input files from the command line
		for ( int i = optind; i < argc; i++ )
			[files addObject: [NSURL fileURLWithPath: [NSString stringWithUTF8String: argv[optind]]]];
	}
	else
	{
		NSData * data = [[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile];
		if ( [data length] != 0 )
		{
			NSString * complete = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
			[complete enumerateLinesUsingBlock: ^(NSString *line, BOOL *stop)
			{
				// stop on an empty line
				if ( [line length] == 0 )
				{
					*stop = YES;
					return;
				}
				
				[files addObject: [NSURL fileURLWithPath: line]];
			}];
		}
	}
	
	if ( [files count] == 0 )
		usage( stderr, EX_USAGE );	// dead call, terminates app
	
	__block int result = EX_OK;
	
	// Use some concurrency if available-- makes more sense when files are being thrown in by a script somewhere.
	// That said, it would make sense if I added the ability to input files using stdin (empty-line terminated?).
	[files enumerateObjectsWithOptions: NSEnumerationConcurrent usingBlock: ^(id fileURL, NSUInteger idx, BOOL *stop)
	{
		if ( [[NSFileManager defaultManager] fileExistsAtPath: [fileURL path]] == NO )
		{
			fprintf( stderr, "File not found: %s", argv[optind] );
			fflush( stderr );
			result = EX_DATAERR;
			*stop = YES;
			return;
		}
		
		// got all the URLs we need now
		
		// get the file's UTI
		NSString * uti = [[fileURL resourceValuesForKeys: [NSArray arrayWithObject: NSURLTypeIdentifierKey] error: NULL] objectForKey: NSURLTypeIdentifierKey];
		
		// remove any old usro resource
		// if an app wasn't specified then we only remove the resource
		RemoveUsroResource( fileURL );
		if ( appURL == nil )
		{
			[fileURL setResourceValue: [NSNull null] forKey: NSURLCustomIconKey error: NULL];
			return;
		}
		
		InstallUsroResource( fileURL, appURL );
		NSImage * customIcon = GetAppFileIcon( appURL, fileURL, uti );
		if ( customIcon != nil )
		{
			if ( [fileURL setResourceValue: customIcon forKey: NSURLCustomIconKey error: NULL] == NO )
			{
				fprintf( stderr, "Failed to set custom icon for file.\n" );
				fflush( stderr );
				result = EX_SOFTWARE;
				*stop = YES;
				return;
			}
		}
	}];
	
    return ( result );
}
