# SMCWrapper
### A little OOP colour around a grey API.

#### What is SMCWrapper?

If you've ever looked under the hood at a Mac OS X application for controlling fans or reading sensor data, then you will undoubtedly have seen two files - ```smc.c``` and ```smc.h```. Used in just about every project that relies upon reading SMC values.

The problem is, these files have become something of a dark magic - with no real comments or explanations anywhere, no bindings for ```NS*``` classes and a lack of any OOP implementation.

To combat that I've done the following;

- Wrapped the functionality up in to a convenient class
- Wrote some fairly extensive comments
- Included the ability to read values in to ```NSNumber``` and ```NSString``` objects.


##### Limitations

###### No Writing to SMC Keys
If people do want this then I will add it in, at some point. Alternatively, fork this and give me a pull request!

###### Limited support for dataTypes
Well, this is **actually a lie** - as this supports more data types than some of the older copies of ```smc.c``` that are still dotted around the internet. However, don't go expecting every possible SMC key to return a valid value. If you find a key that doesn't, please fill in an *"Issue"* here on Github and I'll have a look at it. (Or, once again, fork it!)

###### Written by someone with a poor grasp of Objective-C
I haven't used Objective C since the days of the iPhone SDK (that's before the iPad came along and it was renamed the iOS SDK for you newcomers! *;)*) - so I'm very much rusty! 

#### Staggeringly Simple

###### Retrieve an instance of SMCWrapper

    SMCWrapper *smc = [SMCWrapper sharedWrapper];

###### Read a key in to an ```NSNumber```

    NSNumber *CPUTemp;
    [smc readKey:"TC0P" intoNumber:&CPUTemp];

###### Read a key in to an ```NSString```

    NSString *fanRPM;
    [smc readKey:"F0Ac" asString:&fanRPM]; 

#### An example

    int main(int argc, const char * argv[])
    {
        SMCWrapper *smc = [SMCWrapper sharedWrapper];
    
        // TC0P => CPU Temperature
        NSNumber *temp;
        if ( [smc readKey:"TC0P" intoNumber:&temp] ){
            NSLog(@"CPU Temperature:\t %@C", [temp stringValue]);
        }
        
        // F0Ac => Fan0 Actual RPM
        NSNumber *fanRPM;
        if ( [smc readKey:"F0Ac" intoNumber:&fanRPM] ){
            NSLog(@"Fan #0 RPM:\t %@", [fanRPM stringValue]);
        }
    
        // F0Mn => Min RPM
        NSString *minRPM;
        if ( [smc readKey:"F0Mn" asString:&minRPM] ){
            NSLog(@"Fan #0 Min RPM:\t %@", minRPM);
        }
    
        // F0Mx => Max RPM
        NSString *maxRPM;
        if ( [smc readKey:"F0Mx" asString:&maxRPM] ){
            NSLog(@"Fan #0 Max RPM:\t %@", maxRPM);
        }
        
        return 0;
    }

On my 13" Early 2004 MacBook Air, this currently produces..

> **2014-09-30 02:48:22.485 SMCInfo[56428:386055]** CPU Temperature:	 42.75C <br/>
> **2014-09-30 02:48:22.487 SMCInfo[56428:386055]** Fan #0 RPM:	 1203 <br/>
> **2014-09-30 02:48:22.487 SMCInfo[56428:386055]** Fan #0 Min RPM:	 1200.00 <br/>
> **2014-09-30 02:48:22.488 SMCInfo[56428:386055]** Fan #0 Max RPM:	 6500.00 

#### License
I'm fairly certain that the original files were wrote by a guy named *devnull*, but released under the GNU General Public License all the same. As such, this class itself is also released under the GNU General Public License.

Special mentions are deserved for [@HHoltmann - Hendrik Holtmann](https://github.com/hholtmann), for his [smcFanControl](https://github.com/hholtmann/smcFanControl) repository which provided some good reading, [@stny - Naoya SATO](https://github.com/stny) for his [Thermo](https://github.com/stny/Thermo) repository - which included an ```smc.c``` version which supported a good number of data types.