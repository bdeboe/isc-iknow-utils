/// <p>Simple <class>%iKnow.Source.Converter</class> implementation that tries to
/// prevent common key-value-ish patterns from messing up iKnow output.</p>
/// <p>Accepted parameters:
/// <ol>
/// <li>$list or comma-separated list of metadata keys to (try to) extract</li>
/// </ol>
/// This class is not designed for superb performance.
Class bdb.iKnow.Converters.SemiStructured Extends %iKnow.Source.Converter
{

Property ExtractMetadata As %String;

Property REBreak As %Regex.Matcher;

Property REMeta As %Regex.Matcher;

Method %OnNew(params As %String) As %Status [ Private, ServerOnly = 1 ]
{
    set ..REBreak = ##class(%Regex.Matcher).%New("([\r\n\t]+|( {3,}))(([A-Z ]+)|([A-Z]?[a-z]+)):")
	kill ^||IK.Conv, ^||IK.ConvDone
    quit ##super($g(params))
}

Method SetParams(params As %String) As %Status
{
    set ..Params = params,
        ..ExtractMetadata = ..GetMetadataKeys($g(params))
    if (..ExtractMetadata'="") {
        set ..REMeta = ##class(%Regex.Matcher).%New("([\r\n\t]+|( {3,}))("_$lts(..ExtractMetadata,"|")_") *: *(\S+ ?)+([\r\n\t]+| {3,})")
    } else {
        set ..REMeta = ""
    }
	kill ^||IK.Conv, ^||IK.ConvDone
	quit $$$OK
}

ClassMethod GetMetadataKeys(params As %String) As %List
{
	if $listvalid($g(params)) && $ld(params,1,extractMetadata) {
		set keys = $s($listvalid(extractMetadata):extractMetadata, 1:$lfs(extractMetadata))
	} elseif (params'="") {
        set keys = $lfs(params)
	} else {
        quit ""
    }
    set stripped = "", ptr = 0
    while $listnext(keys,ptr,key) {
        set stripped = stripped _ $lb($zstrip(key,"<>W"))
    }
    quit stripped
}

/// Buffer data in a PPG
Method BufferString(data As %String) As %Status
{
	set ^||IK.Conv($i(^||IK.Conv)) = data
	quit $$$OK
}

Method Convert() As %Status
{
    set sc = $$$OK
    try {
        set nlbr = $c(13,10)

        set i = ""
        for {
            set i = $order(^||IK.Conv(i), 1, data)
            quit:i=""

            set ..REBreak.Text = data
            set ^||IK.ConvDone($i(^||IK.ConvDone)) = ..REBreak.ReplaceAll(nlbr_nlbr_"$3:")

            if $isobject(..REMeta) {
                set ..REMeta.Text = $s(i=1:nlbr, 1:"")_data_nlbr,  // make sure first line keys can be caught
                    pos = 0
                while ..REMeta.Locate(pos) {
                    set meta($zstrip(..REMeta.Group(3),"<>W")) = $zstrip(..REMeta.Group(4),"<>W"),
                        pos = ..REMeta.End-$l(..REMeta.Group(5)) // make sure we catch overlapping line breaks
                }
            }
        }
        
        if $d(meta) {
            set metaValues = ""
            for i = 1:1:$ll(..ExtractMetadata) {
                set metaValues = metaValues_$lb($g(meta($li(..ExtractMetadata,i))))
            }
            do ..SetCurrentMetadataValues(metaValues)
        }
        set ^||IK.ConvDone=0
    
    } catch (ex) {
        set sc = ex.AsStatus()
    }
    quit sc
}

/// Loop through the PPG again and return processed strings.
Method NextConvertedPart() As %String
{
	set currentIndex = $g(^||IK.ConvDone)
	set nextIndex = $order(^||IK.ConvDone(currentIndex),1,string)
	
	if (nextIndex="") {
		kill ^||IK.ConvDone, ^||IK.Conv
		quit ""
	}
	set ^||IK.ConvDone = nextIndex
	
	quit string
}

/// Slight extension to base <method>Test</method>
ClassMethod TestFull(ByRef input As %String, params As %List = "", Output metadata, Output sc As %Status) As %String
{
    kill metadata
	set sc = $$$OK, 
        convertedText = ""
	try {
		set converter = ..%New(params)
		
		if $d(input)>1 {
			set i = ""
			for {
				set i = $order(input(i), 1, text)
				quit:i=""
				set sc = converter.BufferString(text)
				quit:$$$ISERR(sc)
			}
			quit:$$$ISERR(sc)
		} else {
			set sc = converter.BufferString(input)
			quit:$$$ISERR(sc)
		}
		
		set sc = converter.Convert()
		quit:$$$ISERR(sc)
		
		while 1 {
			set line = converter.NextConvertedPart()
			quit:line=""
			set convertedText = convertedText _ line
		}

        set metaKeys = converter.GetMetadataKeys(params)
        set metaValues = converter.GetMetadataValues()
        for i = 1:1:$ll(metaKeys) {
            set metadata($li(metaKeys,i)) = $lg(metaValues,i)
        }
		
		set converter=""
		
	} catch (ex) {
		set sc = ex.AsStatus()
	}
	quit convertedText
}

}
