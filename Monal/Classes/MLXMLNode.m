//
//  XMLNode.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/29/13.
//
//

#import "MLXMLNode.h"

#import "HelperTools.h"
#import "XMPPIQ.h"
#import "XMPPMessage.h"
#import "XMPPPresence.h"
#import "XMPPDataForm.h"


//weak container holding an object as weak pointer (needed to not create retain circles in NSCache
@interface WeakContainer : NSObject
@property (nonatomic, weak) id obj;
@end
@implementation WeakContainer
-(id) initWithObj:(id) obj
{
    self = [super init];
    self.obj = obj;
    return self;
}
@end


@interface MLXMLNode()
{
    NSMutableArray* _children;
}
@property (nonatomic, strong) NSCache* cache;
@property (nonatomic, strong) NSCache* queryEntryCache;

@property (atomic, strong, readwrite) NSString* element;
@property (atomic, readwrite) NSMutableDictionary* attributes;
@property (atomic, weak, readwrite) MLXMLNode* parent;
@end

@implementation MLXMLNode

static NSRegularExpression* pathSplitterRegex;
static NSRegularExpression* componentParserRegex;
static NSRegularExpression* attributeFilterRegex;

#ifdef QueryStatistics
    static NSMutableDictionary* statistics;
#endif

+(void) initialize
{
#ifdef QueryStatistics
    statistics = [[NSMutableDictionary alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(nowIdle:) name:kMonalIdle object:nil];
#endif
    
    //compile regexes only once (see https://unicode-org.github.io/icu/userguide/strings/regexp.html for syntax)
    pathSplitterRegex = [NSRegularExpression regularExpressionWithPattern:@"^(/?(\\{(\\*|[^}]+)\\})?([!a-zA-Z0-9_:-]+|\\*|\\.\\.)?((\\<[^=~]+[=~][^>]+\\>)*))((/((\\{(\\*|[^}]+)\\})?([!a-zA-Z0-9_:-]+|\\*|\\.\\.)?((\\<[^=]+=[^>]+\\>)*)))*)((@[a-zA-Z0-9_:-]+|@@|#|\\$|\\\\[^\\\\]+\\\\)(\\|(bool|int|float|datetime|base64))?)?$" options:NSRegularExpressionCaseInsensitive error:nil];
    componentParserRegex = [NSRegularExpression regularExpressionWithPattern:@"^(\\{(\\*|[^}]+)\\})?([!a-zA-Z0-9_:-]+|\\*|\\.\\.)?((\\<[^=~]+[=~][^>]+\\>)*)((@[a-zA-Z0-9_:-]+|@@|#|\\$|\\\\[^\\\\]+\\\\)(\\|(bool|int|float|datetime|base64))?)?$" options:NSRegularExpressionCaseInsensitive error:nil];
    attributeFilterRegex = [NSRegularExpression regularExpressionWithPattern:@"\\<([^=~]+)([=~])([^>]+)\\>" options:NSRegularExpressionCaseInsensitive error:nil];

//     testcases for stanza
//     <stream:features><mechanisms xmlns='urn:ietf:params:xml:ns:xmpp-sasl'><mechanism>SCRAM-SHA-1</mechanism><mechanism>PLAIN</mechanism><mechanism>SCRAM-SHA-1-PLUS</mechanism></mechanisms></stream:features>
//     [self print_debug:@"/*" inTree:parsedStanza];
//     [self print_debug:@"{*}*" inTree:parsedStanza];
//     [self print_debug:@"{*}*/*@xmlns" inTree:parsedStanza];
//     [self print_debug:@"{urn:ietf:params:xml:ns:xmpp-sasl}mechanisms" inTree:parsedStanza];
//     [self print_debug:@"{*}*@xmlns" inTree:parsedStanza];
//     [self print_debug:@"{urn:ietf:params:xml:ns:xmpp-sasl}mechanisms/mechanism" inTree:parsedStanza];
//     [self print_debug:@"{urn:ietf:params:xml:ns:xmpp-sasl}mechanisms/mechanism#" inTree:parsedStanza];
//     [self print_debug:@"{urn:ietf:params:xml:ns:xmpp-sasl}mechanisms/*#" inTree:parsedStanza];
//     [self print_debug:@"{urn:ietf:params:xml:ns:xmpp-sasl}mechanisms/*@xmlns" inTree:parsedStanza];
//     [self print_debug:@"/.." inTree:parsedStanza];
//     [self print_debug:@"/../*" inTree:parsedStanza];
//     [self print_debug:@"mechanisms/mechanism#" inTree:parsedStanza];
//     [self print_debug:@"{jabber:client}iq@@" inTree:parsedStanza];
}

+(void) nowIdle:(NSNotification*) notification
{
#ifdef QueryStatistics
    NSMutableDictionary* sortedStatistics = [[NSMutableDictionary alloc] init];
    @synchronized(statistics) {
        NSArray* sortedKeys = [statistics keysSortedByValueUsingComparator: ^(id obj1, id obj2) {
            if([obj1 integerValue] > [obj2 integerValue])
                return (NSComparisonResult)NSOrderedDescending;
            if([obj1 integerValue] < [obj2 integerValue])
                return (NSComparisonResult)NSOrderedAscending;
            return (NSComparisonResult)NSOrderedSame;
        }];
        for(NSString* key in sortedKeys)
            DDLogDebug(@"STATISTICS: %@ = %@", key, statistics[key]);
            //sortedStatistics[key] = statistics[key];
    }
    //DDLogDebug(@"XML QUERY STATISTICS: %@", sortedStatistics);
#endif
}

-(void) internalInit
{
    _attributes = [[NSMutableDictionary alloc] init];
    _children = [[NSMutableArray alloc] init];
    _parent = nil;
    _data = nil;
    _element = @"";
    self.cache = [[NSCache alloc] init];
    self.queryEntryCache = [[NSCache alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleMemoryPressureNotification) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
}

-(id) init
{
    self = [super init];
    [self internalInit];
    return self;
}

-(id) initWithElement:(NSString*) element
{
    self = [super init];
    [self internalInit];
    _element = [element copy];
    return self;
}

-(id) initWithElement:(NSString*) element andNamespace:(NSString*) xmlns
{
    self = [self initWithElement:element];
    [self setXMLNS:xmlns];
    return self;
}

-(id) initWithElement:(NSString*) element andNamespace:(NSString*) xmlns withAttributes:(NSDictionary*) attributes andChildren:(NSArray*) children andData:(NSString*) data
{
    self = [self initWithElement:element withAttributes:attributes andChildren:children andData:data];
    [self setXMLNS:xmlns];
    return self;
}

-(id) initWithElement:(NSString*) element withAttributes:(NSDictionary*) attributes andChildren:(NSArray*) children andData:(NSString*) data
{
    self = [self initWithElement:element];
    [_attributes addEntriesFromDictionary:[[NSDictionary alloc] initWithDictionary:attributes copyItems:YES]];
    for(MLXMLNode* child in children)
        [self addChildNode:child];
    _data = nil;
    if(data)
        _data = [data copy];
    return self;
}

-(id) initWithElement:(NSString*) element andData:(NSString* _Nullable) data
{
    self = [self initWithElement:element withAttributes:@{} andChildren:@[] andData:data];
    return self;
}

-(void) deinit
{
    DDLogVerbose(@"Deinit of MLXMLNode: %@", self);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.cache removeAllObjects];
    [self.queryEntryCache removeAllObjects];
}

-(id) initWithCoder:(NSCoder*) decoder
{
    self = [super init];
    if(!self)
        return nil;
    [self internalInit];

    _element = [decoder decodeObjectOfClass:[NSString class] forKey:@"element"];
    _attributes = [decoder decodeObjectOfClasses:[[NSSet alloc] initWithArray:@[[NSMutableDictionary class], [NSDictionary class], [NSMutableString class], [NSString class]]] forKey:@"attributes"];
    NSArray* decodedChildren = [decoder decodeObjectOfClasses:[[NSSet alloc] initWithArray:@[[NSMutableArray class], [NSArray class], [MLXMLNode class], [XMPPIQ class], [XMPPMessage class], [XMPPPresence class], [XMPPDataForm class]]] forKey:@"children"];
    for(MLXMLNode* child in decodedChildren)
        [self addChildNode:child];
    _data = [decoder decodeObjectOfClass:[NSString class] forKey:@"data"];

    return self;
}

-(void) encodeWithCoder:(NSCoder*) encoder
{
    [encoder encodeObject:_element forKey:@"element"];
    [encoder encodeObject:_attributes forKey:@"attributes"];
    [encoder encodeObject:_children forKey:@"children"];
    [encoder encodeObject:_data forKey:@"data"];
}

+(BOOL) supportsSecureCoding
{
    return YES;
}

-(id) copyWithZone:(NSZone*) zone
{
    MLXMLNode* copy = [[[self class] alloc] initWithElement:_element];
    copy.attributes = [[NSMutableDictionary alloc] initWithDictionary:_attributes copyItems:YES];
    for(MLXMLNode* child in _children)
        [copy addChildNode:child];
    copy.data = _data ? [_data copy] : nil;
    return copy;
}

-(void) handleMemoryPressureNotification
{
    [self.cache removeAllObjects];
    [self.queryEntryCache removeAllObjects];
    DDLogVerbose(@"Removed all cached objects in this MLXMLNode due to memory pressure");
    DDLogVerbose(@"Node: %@", self);
}

-(void) setXMLNS:(NSString*) xmlns
{
    [_attributes setObject:[xmlns copy] forKey:kXMLNS];
}

-(MLXMLNode*) addChildNode:(MLXMLNode*) child
{
    if(!child)
        return nil;
    MLXMLNode* insertedChild = [child copy];
    insertedChild.parent = self;
    //namespace inheritance (will be stripped by XMLString later on)
    //we do this here to make sure manual created nodes always have a namespace like the nodes created by the xml parser do
    if(!insertedChild.attributes[@"xmlns"])
        insertedChild.attributes[@"xmlns"] = _attributes[@"xmlns"];
    [_children addObject:insertedChild];
    [self invalidateUpstreamCache];
    //this one can be removed if the query path component ".." is removed from our language
    [insertedChild invalidateDownstreamCache];
    return insertedChild;
}

-(MLXMLNode*) removeChild:(MLXMLNode*) child
{
    MLXMLNode* foundChild = nil;
    if(!child)
        return foundChild;
    NSInteger index = [_children indexOfObject:child];
    if(index != NSNotFound)
    {
        foundChild = [_children objectAtIndex:index];
        foundChild.parent = nil;
        [_children removeObjectAtIndex:index];
        [self invalidateUpstreamCache];
    }
    return foundChild;
}

-(NSArray*) children
{
    return [NSArray arrayWithArray:_children];
}

-(void) invalidateUpstreamCache
{
    //invalidate caches of all nodes upstream in our tree
    for(MLXMLNode* node = self; node; node = node.parent)
        [node.cache removeAllObjects];
}

-(void) invalidateDownstreamCache
{
    [self.cache removeAllObjects];
    for(MLXMLNode* node in _children)
        [node invalidateDownstreamCache];
}

//query language similar to the one prosody uses (which in turn is loosely based on xpath)
//this implements a strict superset of prosody's language which makes it possible to use queries from prosody directly
//unlinke the language used in prosody, this returns *all* nodes mathching the query (use findFirst to get only the first match like prosody does)
//see https://prosody.im/doc/developers/util/stanza (function stanza:find(path)) for examples and description
//extensions to prosody's language:
//we extended this language to automatically infer the namespace from the parent element, if no namespace was given explicitly in the query
//we also added support for "*" as element name or namespace meaning "any nodename" / "any namespace"
//the additional ".." element name can be used to ascend to the parent node and do a find() on this node using the rest of the query path
//if you begin a path with "/" that means "begin with checking the current element", if your path does not begin with a "/"
//this means "begin witch checking the children of this node" (normal prosody behaviour)
//we also added additional extraction commands ("@attrName" and "#" are extraction commands defined within prosody):
//extraction command "$" returns the name of the XML element (just like "#" returns its text content)
//the argument "@" for extraction command "@" returns the full attribute dictionary of the XML element (full command: "@@")
//we also added conversion commands that can be appended to a query string:
//"|bool" --> convert xml string to bool (XMPP defines "1"/"true" to be true and "0"/"false" to be false)
//"|int" --> convert xml string to NSNumber
//"|float" --> convert xml string to NSNumber
//"|datetime" --> convert xml datetime string to NSDate
//"|base64" --> convert base64 encoded xml string to NSData
-(NSArray*) find:(NSString* _Nonnull) queryString, ... NS_FORMAT_FUNCTION(1, 2)
{
    va_list args;
    va_start(args, queryString);
    NSArray* retval = [self find:queryString arguments:args];
    va_end(args);
    return retval;
}

//like find: above, but only return the first match
-(id) findFirst:(NSString* _Nonnull) queryString, ... NS_FORMAT_FUNCTION(1, 2)
{
    va_list args;
    va_start(args, queryString);
    id retval = [self find:queryString arguments:args].firstObject;
    va_end(args);
    return retval;
}

//like findFirst, but only check if it would return something
-(BOOL) check:(NSString* _Nonnull) queryString, ... NS_FORMAT_FUNCTION(1, 2)
{
    va_list args;
    va_start(args, queryString);
    BOOL retval = [self find:queryString arguments:args].firstObject != nil ? YES : NO;
    va_end(args);
    return retval;
}

-(NSArray*) find:(NSString* _Nonnull) queryString arguments:(va_list) args
{
    //return our own node if the query string is empty (this makes queries like "/.." possible which will return the parent node
    if(!queryString || [queryString isEqualToString:@""])
        return @[self];
    
    va_list cacheKeyArgs;
    va_copy(cacheKeyArgs, args);
    NSString* cacheKey = [NSString stringWithFormat:@"%@§§%@", queryString, [[NSString alloc] initWithFormat:queryString arguments:cacheKeyArgs]];
    va_end(cacheKeyArgs);
    
    //return results from cache if possible
    WeakContainer* cacheEntryContainer = [self.cache objectForKey:cacheKey];
    if(cacheEntryContainer != nil && cacheEntryContainer.obj != nil)
        return (NSArray*)cacheEntryContainer.obj;
    
#ifdef QueryStatistics
    @synchronized(statistics) {
        if(!statistics[queryString])
            statistics[queryString] = @0;
        statistics[queryString] = [NSNumber numberWithInteger:[statistics[queryString] integerValue] + 1];
    }
#endif
    
    //shortcut syntax for queries operating directly on this node
    //this translates "/@attr", "/#" or "/$" into their correct form "/{*}*@attr", "/{*}*#" or "/{*}*$"
    if(
        [queryString characterAtIndex:0] == '/' &&
        [queryString length] >=2 &&
        [[NSCharacterSet characterSetWithCharactersInString:@"@#$<"] characterIsMember:[queryString characterAtIndex:1]]
    )
        queryString = [NSString stringWithFormat:@"/{*}*%@", [queryString substringFromIndex:1]];
    
    NSArray* results;
    //check if the current element our our children should be queried "/" makes the path "absolute" instead of "relative"
    if([[queryString substringToIndex:1] isEqualToString:@"/"])
        results = [self find:[queryString substringFromIndex:1] inNodeList:@[self] arguments:args];        //absolute path (check self first)
    else
        results = [self find:queryString inNodeList:_children arguments:args];                             //relative path (check childs first)
    
    //update cache and return results
    [self.cache setObject:[[WeakContainer alloc] initWithObj:results] forKey:cacheKey];                    //use weak container to break retain circle
    return results;
}

-(NSArray*) find:(NSString* _Nonnull) queryString inNodeList:(NSArray* _Nonnull) nodesToCheck arguments:(va_list) args
{
    //shortcut for empty nodesToCheck
    if(![nodesToCheck count])
        return @[];
    NSMutableArray* results = [[NSMutableArray alloc] init];
    //split our path into first component and rest
    NSArray* matches = [pathSplitterRegex matchesInString:queryString options:0 range:NSMakeRange(0, [queryString length])];
    if(![matches count])
        @throw [NSException exceptionWithName:@"RuntimeException" reason:@"XML query has syntax errors (no matches for path splitter regex)!" userInfo:@{
            @"self": self,
            @"queryString": queryString,
        }];
    NSTextCheckingResult* match = matches.firstObject;
    NSRange pathComponent1Range = [match rangeAtIndex:1];
    NSRange pathComponent2Range = [match rangeAtIndex:7];
    NSRange pathComponent3Range = [match rangeAtIndex:15];
    NSString* pathComponent1 = @"";
    NSString* pathComponent2 = @"";
    NSString* pathComponent3 = @"";
    if(pathComponent1Range.location != NSNotFound && pathComponent1Range.length > 0)
        pathComponent1 = [queryString substringWithRange:pathComponent1Range];
    if(pathComponent2Range.location != NSNotFound && pathComponent2Range.length > 0)
        pathComponent2 = [queryString substringWithRange:pathComponent2Range];
    if(pathComponent3Range.location != NSNotFound && pathComponent3Range.length > 0)
        pathComponent3 = [queryString substringWithRange:pathComponent3Range];
    
    NSString* pathComponent = pathComponent1;
    NSString* rest = @"";
    if(![pathComponent2 length])
        pathComponent = [NSString stringWithFormat:@"%@%@", pathComponent1, pathComponent3];
    else
        rest = [NSString stringWithFormat:@"%@%@", [pathComponent2 substringFromIndex:1], pathComponent3];
    NSMutableDictionary* parsedEntry = [self parseQueryEntry:pathComponent arguments:args];
    
    //check if the parent element was selected and ask our parent to check the rest of our query path if needed
    if([pathComponent isEqualToString:@".."])
    {
        MLXMLNode* parent = self.parent;
        if(!parent)
            @throw [NSException exceptionWithName:@"RuntimeException" reason:@"XML query tries to ascend to non-existent parent element!" userInfo:@{
                @"self": self,
                @"queryString": queryString,
                @"pathComponent": pathComponent,
                @"parsedEntry": parsedEntry
            }];
        return [parent find:rest arguments:args];
    }
    
    //shortcut for dataform subqueries: allow empty element names and namespaces, they get autofilled with {jabber:x:data}x
    if(!parsedEntry[@"elementName"] && !parsedEntry[@"namespace"] && [parsedEntry[@"extractionCommand"] isEqualToString:@"\\"])
    {
        parsedEntry[@"elementName"] = @"x";
        parsedEntry[@"namespace"] = @"jabber:x:data";
    }
    
    if(!parsedEntry[@"elementName"] && !parsedEntry[@"namespace"])
        @throw [NSException exceptionWithName:@"RuntimeException" reason:@"XML queries must not contain a path component having neither element name nor namespace!" userInfo:@{
            @"self": self,
            @"queryString": queryString,
            @"pathComponent": pathComponent,
            @"parsedEntry": parsedEntry
        }];
    
    //"*" is just syntactic sugar for an empty element name
    //(but empty element names are not allowed if no namespace was given, which makes this sugar mandatory in this case)
    if(parsedEntry[@"elementName"] && [parsedEntry[@"elementName"] isEqualToString:@"*"])
        [parsedEntry removeObjectForKey:@"elementName"];
    
    //if no namespace was given, use the parent one (no namespace means the namespace will be inherited)
    //this will allow all namespaces "{*}" if the nodes in nodesToCheck don't have a parent at all
    if((!parsedEntry[@"namespace"] || [parsedEntry[@"namespace"] isEqualToString:@""]) && ((MLXMLNode*)nodesToCheck[0]).parent)
        parsedEntry[@"namespace"] = ((MLXMLNode*)nodesToCheck[0]).parent.attributes[@"xmlns"];      //all nodesToCheck have the same parent, just pick the first one
    
    //"*" is just syntactic sugar for an empty namespace name which means "any namespace allowed"
    //(but empty namespaces are only allowed in internal methods, which makes this sugar mandatory)
    //don't confuse this with a query without namespace which will result in a query using the parent's namespace, not "any namespace allowed"!
    if(parsedEntry[@"namespace"] && [parsedEntry[@"namespace"] isEqualToString:@"*"])
        [parsedEntry removeObjectForKey:@"namespace"];
    
    //element names can be negated
    BOOL negatedElementName = NO;
    if(parsedEntry[@"elementName"] && [parsedEntry[@"elementName"] characterAtIndex:0] == '!')
    {
        negatedElementName = YES;
        parsedEntry[@"elementName"] = [parsedEntry[@"elementName"] substringFromIndex:1];
    }
    
    //iterate through nodesToCheck (containing only us, our parent's children or our own children)
    //and check if they match the current path component (e.g. parsedEntry)
    for(MLXMLNode* node in nodesToCheck)
    {
        //check element name and namespace (if given)
        if(
            (
                (negatedElementName && ![parsedEntry[@"elementName"] isEqualToString:node.element]) ||
                (!parsedEntry[@"elementName"] || [parsedEntry[@"elementName"] isEqualToString:node.element])
            ) &&
            (!parsedEntry[@"namespace"] || [parsedEntry[@"namespace"] isEqualToString:node.attributes[@"xmlns"]])
        ) {
            //check for attribute filters (if given)
            if(parsedEntry[@"attributeFilters"] && [parsedEntry[@"attributeFilters"] count])
            {
                BOOL ok = YES;
                for(NSDictionary* filter in parsedEntry[@"attributeFilters"])
                {
                    if(node.attributes[filter[@"name"]])
                    {
                        NSArray* matches = [filter[@"value"] matchesInString:node.attributes[filter[@"name"]] options:0 range:NSMakeRange(0, [node.attributes[filter[@"name"]] length])];
                        if(![matches count])
                        {
                            ok = NO;        //this node does *not* fullfill the attribute filter regex
                            break;
                        }
                    }
                    else
                    {
                        ok = NO;
                        break;
                    }
                }
                if(!ok)
                    continue;               //this node does *not* fullfill the attribute filter regex
            }
            //check if we should process an extraction command (only allowed if we're at the end of the query)
            if(parsedEntry[@"extractionCommand"])
            {
                //sanity check
                if([rest length] > 0)
                    @throw [NSException exceptionWithName:@"RuntimeException" reason:@"Extraction commands are only allowed for terminal nodes of XML queries!" userInfo:@{
                        @"self": self,
                        @"node": node,
                        @"queryString": queryString,
                        @"pathComponent": pathComponent,
                        @"parsedEntry": parsedEntry
                    }];
                
                id singleResult = nil;
                if([parsedEntry[@"extractionCommand"] isEqualToString:@"#"] && node.data)
                    singleResult = [self processConversionCommand:parsedEntry[@"conversionCommand"] forXMLString:node.data];
                else if([parsedEntry[@"extractionCommand"] isEqualToString:@"@"] && node.attributes[parsedEntry[@"attribute"]])
                    singleResult = [self processConversionCommand:parsedEntry[@"conversionCommand"] forXMLString:node.attributes[parsedEntry[@"attribute"]]];
                else if([parsedEntry[@"extractionCommand"] isEqualToString:@"$"] && node.element)
                    singleResult = [self processConversionCommand:parsedEntry[@"conversionCommand"] forXMLString:node.element];
                else if([parsedEntry[@"extractionCommand"] isEqualToString:@"\\"])
                {
                    if(![node respondsToSelector:NSSelectorFromString(@"processDataFormQuery:")])
                        @throw [NSException exceptionWithName:@"RuntimeException" reason:@"Data form extractions can only be used on data forms! This exception means you have a bug somewhere else in your code (probably at the source of the element you are trying to use in your data form query)!" userInfo:@{
                            @"self": self,
                            @"node": node,
                            @"queryString": queryString,
                            @"pathComponent": pathComponent,
                            @"parsedEntry": parsedEntry
                        }];
                    //faster than NSMethodInvocation, but way less readable, see https://stackoverflow.com/a/20058585/3528174
                    id extraction = ((id (*)(id, SEL, NSString*))[node methodForSelector:NSSelectorFromString(@"processDataFormQuery:")])(node, NSSelectorFromString(@"processDataFormQuery:"), parsedEntry[@"dataFormQuery"]);
                    if(extraction)      //only add this to our results if the data form query succeeded
                    {
                        //check if we try to operate a conversion command on something not a single extracted simple form field of type NSString
                        if(parsedEntry[@"conversionCommand"] && ![extraction isKindOfClass:[NSString class]])
                            @throw [NSException exceptionWithName:@"RuntimeException" reason:@"Conversion commands can not be used on data form extractions returning the whole data form or an NSArray/NSDictionary!" userInfo:@{
                                @"self": self,
                                @"node": node,
                                @"queryString": queryString,
                                @"pathComponent": pathComponent,
                                @"parsedEntry": parsedEntry
                            }];
                        singleResult = [self processConversionCommand:parsedEntry[@"conversionCommand"] forXMLString:(NSString*)extraction];
                    }
                }
                else if([parsedEntry[@"extractionCommand"] isEqualToString:@"@"] && [parsedEntry[@"attribute"] isEqualToString:@"@"])
                {
                    if(parsedEntry[@"conversionCommand"])
                        @throw [NSException exceptionWithName:@"RuntimeException" reason:@"Conversion commands can not be used on attribute dict extractions (e.g. extraction command '@@')!" userInfo:@{
                            @"self": self,
                            @"node": node,
                            @"queryString": queryString,
                            @"pathComponent": pathComponent,
                            @"parsedEntry": parsedEntry
                        }];
                    singleResult = node.attributes;
                }
                if(singleResult)
                    [results addObject:singleResult];
            }
            else
            {
                if(parsedEntry[@"conversionCommand"])
                    @throw [NSException exceptionWithName:@"RuntimeException" reason:@"Conversion commands are only allowed for terminal nodes of XML queries that use an extraction command!" userInfo:@{
                        @"self": self,
                        @"node": node,
                        @"queryString": queryString,
                        @"pathComponent": pathComponent,
                        @"parsedEntry": parsedEntry
                    }];
                if([rest length] > 0)            //we should descent to this node
                    [results addObjectsFromArray:[node find:rest arguments:args]];     //this will cache the subquery on this node, too
                else                            //we should not descent to this node (we reached the end of our query)
                    [results addObject:node];
            }
        }
    }
    
    //DDLogVerbose(@"*** DEBUG(%@)[%@] ***\n%@\n%@\n%@", queryString, pathComponent, parsedEntry, results, nodesToCheck);
    return [results copy];       //return readonly copy of results
}

-(id) processConversionCommand:(NSString*) command forXMLString:(NSString* _Nonnull) string
{
    if(!string)
        return nil;
    if([command isEqualToString:@"bool"])
    {
        //xml bools as defined in xmpp core RFC
        if([string isEqualToString:@"1"] || [string isEqualToString:@"true"])
            return @YES;
        else if([string isEqualToString:@"0"] || [string isEqualToString:@"false"])
            return @NO;
        else
            return @NO;     //no bool at all, return false
    }
    else if([command isEqualToString:@"int"])
        return [NSNumber numberWithInteger:[string integerValue]];
    else if([command isEqualToString:@"float"])
        return [NSNumber numberWithFloat:[string floatValue]];
    else if([command isEqualToString:@"datetime"])
        return [HelperTools parseDateTimeString:string];
    else if([command isEqualToString:@"base64"])
        return [HelperTools dataWithBase64EncodedString:string];
    else
        return string;
}

-(NSMutableDictionary*) parseQueryEntry:(NSString* _Nonnull) entry arguments:(va_list) args
{
    va_list cacheKeyArgs;
    va_copy(cacheKeyArgs, args);
    NSString* cacheKey = [NSString stringWithFormat:@"%@§§%@", entry, [[NSString alloc] initWithFormat:entry arguments:cacheKeyArgs]];
    va_end(cacheKeyArgs);
    NSDictionary* cacheEntry = [self.queryEntryCache objectForKey:cacheKey];
    if(cacheEntry != nil)
        return [cacheEntry mutableCopy];
    NSMutableDictionary* retval = [[NSMutableDictionary alloc] init];
    NSArray* matches = [componentParserRegex matchesInString:entry options:0 range:NSMakeRange(0, [entry length])];
    if(![matches count])
        @throw [NSException exceptionWithName:@"RuntimeException" reason:@"Could not parse path component!" userInfo:@{
            @"self": self,
            @"queryEntry": entry
        }];
    NSTextCheckingResult* match = matches.firstObject;
    NSRange namespaceRange = [match rangeAtIndex:2];
    NSRange elementNameRange = [match rangeAtIndex:3];
    NSRange attributeFilterRange = [match rangeAtIndex:4];
    NSRange extractionCommandRange = [match rangeAtIndex:7];
    NSRange conversionCommandRange = [match rangeAtIndex:9];
    if(namespaceRange.location != NSNotFound)
        retval[@"namespace"] = [entry substringWithRange:namespaceRange];
    if(elementNameRange.location != NSNotFound)
        retval[@"elementName"] = [entry substringWithRange:elementNameRange];
    if(attributeFilterRange.location != NSNotFound && attributeFilterRange.length > 0)
    {
        retval[@"attributeFilters"] = [[NSMutableArray alloc] init];
        NSString* attributeFilters = [entry substringWithRange:attributeFilterRange];
        NSArray* attributeFilterMatches = [attributeFilterRegex matchesInString:attributeFilters options:0 range:NSMakeRange(0, [attributeFilters length])];
        for(NSTextCheckingResult* attributeFilterMatch in attributeFilterMatches)
        {
            NSRange attributeFilterNameRange = [attributeFilterMatch rangeAtIndex:1];
            NSRange attributeFilterTypeRange = [attributeFilterMatch rangeAtIndex:2];
            NSRange attributeFilterValueRange = [attributeFilterMatch rangeAtIndex:3];
            if(attributeFilterNameRange.location == NSNotFound || attributeFilterTypeRange.location == NSNotFound || attributeFilterValueRange.location == NSNotFound)
                @throw [NSException exceptionWithName:@"RuntimeException" reason:@"Attribute filter not complete!" userInfo:@{
                    @"self": self,
                    @"queryEntry": entry,
                    @"attributeFilters": attributeFilters
                }];
            
            NSString* attributeFilterName = [attributeFilters substringWithRange:attributeFilterNameRange];
            unichar attributeFilterType = [[attributeFilters substringWithRange:attributeFilterTypeRange] characterAtIndex:0];
            NSString* attributeFilterValue = [attributeFilters substringWithRange:attributeFilterValueRange];
            
            NSString* attributeFilterValueRegexPattern;
            if(attributeFilterType == '=')      //verbatim comparison using format string interpolation
            {
                //substitute format string specifiers inside of our attribute filter string
                NSString* unescapedAttributeFilterValue = [[NSString alloc] initWithFormat:attributeFilterValue arguments:args];
                NSString* escapedAttributeFilterValue = [NSRegularExpression escapedPatternForString:unescapedAttributeFilterValue];
                attributeFilterValueRegexPattern = [NSString stringWithFormat:@"^%@$", escapedAttributeFilterValue];
            }
            else if(attributeFilterType == '~')      //raw regex comparison *without* format string interpolation
                //you will have to include sring-start and string-end markers yourself as well as all other regex stuff
                attributeFilterValueRegexPattern = attributeFilterValue;
            else
                @throw [NSException exceptionWithName:@"RuntimeException" reason:@"Internal attribute filter bug, this should never happen!" userInfo:@{
                    @"self": self,
                    @"queryEntry": entry,
                    @"attributeFilters": attributeFilters
                }];
                
            NSError* error;
            [retval[@"attributeFilters"] addObject:@{
                @"name": attributeFilterName,
                //this regex will be cached in parsed form in the local cache of this method
                @"value": [NSRegularExpression regularExpressionWithPattern:attributeFilterValueRegexPattern options:NSRegularExpressionCaseInsensitive error:&error]
            }];
            if(error)
                @throw [NSException exceptionWithName:@"RuntimeException" reason:@"Attribute filter regex can not be compiled!" userInfo:@{
                    @"self": self,
                    @"queryEntry": entry,
                    @"filterType": @(attributeFilterType),
                    @"filterName": attributeFilterName,
                    @"filterValue": attributeFilterValue,
                    @"error": error
                }];
        }
    }
    if(extractionCommandRange.location != NSNotFound)
    {
        NSString* extractionCommand = [entry substringWithRange:extractionCommandRange];
        retval[@"extractionCommand"] = [extractionCommand substringToIndex:1];
        unichar command = [extractionCommand characterAtIndex:0];
        if(command == '@')
            retval[@"attribute"] = [extractionCommand substringFromIndex:1];
        if(command == '\\')
            retval[@"dataFormQuery"] = [extractionCommand substringWithRange:NSMakeRange(1, extractionCommandRange.length-2)];
    }
    if(conversionCommandRange.location != NSNotFound)
        retval[@"conversionCommand"] = [entry substringWithRange:conversionCommandRange];
    [self.queryEntryCache setObject:[retval copy] forKey:cacheKey];
    return retval;
}

+(NSString*) escapeForXMPP:(NSString*) targetString
{
    NSMutableString* mutable = [targetString mutableCopy];
    [mutable replaceOccurrencesOfString:@"&" withString:@"&amp;" options:NSLiteralSearch range:NSMakeRange(0, mutable.length)];
    [mutable replaceOccurrencesOfString:@"<" withString:@"&lt;" options:NSLiteralSearch range:NSMakeRange(0, mutable.length)];
    [mutable replaceOccurrencesOfString:@">" withString:@"&gt;" options:NSLiteralSearch range:NSMakeRange(0, mutable.length)];
    [mutable replaceOccurrencesOfString:@"'" withString:@"&apos;" options:NSLiteralSearch range:NSMakeRange(0, mutable.length)];
    [mutable replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:NSLiteralSearch range:NSMakeRange(0, mutable.length)];
    return [mutable copy];
}

-(NSString*) XMLString
{
    if(!_element)
        return @""; // sanity check
    
    //special handling of xml start tag
    if([_element isEqualToString:@"__xml"])
         return [NSString stringWithFormat:@"<?xml version='1.0'?>"];
    
    NSMutableString* outputString = [[NSMutableString alloc] init];
    [outputString appendString:[NSString stringWithFormat:@"<%@", _element]];
    
    //set attributes
    MLXMLNode* parent = self.parent;
    for(NSString* key in [_attributes allKeys])
    {
        //handle xmlns inheritance (don't add namespace to childs if it should be the same like the parent's one)
        if([key isEqualToString:@"xmlns"] && parent && [_attributes[@"xmlns"] isEqualToString:parent.attributes[@"xmlns"]])
            continue;
        [outputString appendString:[NSString stringWithFormat:@" %@='%@'", key, [MLXMLNode escapeForXMPP:(NSString*)_attributes[key]]]];
    }
    
    if([_children count] || (_data && ![_data isEqualToString:@""]))
    {
        [outputString appendString:[NSString stringWithFormat:@">"]];
        
        //set children here
        for(MLXMLNode* child in _children)
            [outputString appendString:[child XMLString]];
        
        if(_data)
            [outputString appendString:[MLXMLNode escapeForXMPP:_data]];
        
        //dont close stream element
        if(![_element isEqualToString:@"stream:stream"] && ![_element isEqualToString:@"/stream:stream"])
            [outputString appendString:[NSString stringWithFormat:@"</%@>", _element]];
    }
    else
    {
        //dont close stream element
        if(![_element isEqualToString:@"stream:stream"] && ![_element isEqualToString:@"/stream:stream"])
            [outputString appendString:[NSString stringWithFormat:@"/>"]];
        else
            [outputString appendString:[NSString stringWithFormat:@">"]];
    }
    
    return (NSString*)outputString;
}

-(NSString*) description
{
    return [self XMLString];
}

@end
