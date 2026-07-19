So this ecosystem is a set of smart contracts deployed in Polygon mainnet (137) and Amoy testnet (80002). Of course,
users will be able to deploy this as well in their local networks.

The underlying idea is to tie an aesthetic to each address to define some sort of Persona linked to the address.
So a central record will exist to hold each Persona created for an address with something like this:

    // The color for a trait. Only 10 elements.
    enum Color {
	    Black, Blue, DarkBrown, Green, LightBrown, Pink, Purple, Red, White, Yellow
    }

    // A trait is an element to render. It can be a cloth, a body, a hair, ...
    // It should be understood that lotId being 0 means nothing is selected.
    // The first lotId is 1, and will per-deployment (i.e. per-data) stand for
    // REFMAP. Others will / might be added later.
    struct Trait {
        uint128 lotId;
        uint120 itemId;
        Color color;
    }

    // The sex.
    enum Sex { Male, Female }

    // The body color. Male and female have access to images of the same values.
    enum Body { White, Black, Yellow, Orange, Blue, Red, Green, Purple }

    // Whether the character uses simple or standard clothes.
    enum ClothType { Standard, Simple }

    // The different trait types. The body is always resolved from the default
    // lot (which here will be known as lot id 1) in front-end. The `Cloth`
    // category will be, however, unknown / empty to the default lot.
    enum TraitType { Arms, Boots, Chest, Hair, HairTail, Hat, LongShirt, Pants, Shirt, Shoulder, Waist, Cloth }

    // The rendering of a persona (visual aspects of an account).
    struct Persona {
        string name; // The name will be unique among all the personas.
                     // Even perhaps limiting the ability to change this value?
                     // Even perhaps limiting this field to something like [a-z0-9_]+.
        Sex sex;
        Body body;
        ClothType clothType;
        Trait body;
        Trait hair;
        Trait hairTail; // Yes, the hair tail goes separate.
        Trait necklace; // The necklace can come in different tones.
        Trait hat;      // Same for the hat.
        // Left and right hand are not included.
    }

    // The rendering of simple clothes of a persona (when using simple clothes).
    struct SimpleClothing {
        Trait cloth;
    }

    // The rendering of standard clothes of a persona (when using standard clothes).
    struct StandardClothing {
        Trait boots;
        Trait pants;
        Trait shirt;
        Trait chest;
        Trait waist;
        Trait arms;
        Trait longShirt;
        Trait shoulders;
        Trait cloak;
        bool  bootsOverPants;
    }

    // All the registered personas' nicknames.
    mapping(string => address) public personasNames;

    // All the registered personas.
    mapping(address => Persona) public personas;

    // For personas with a .Standard clothing, this structure includes the cloth.
    mapping(address => SimpleClothing) public simpleClothing;

    // For personas with a .Standard clothing, this structure includes the cloth.
    mapping(address => StandardClothing) public standardClothing;

Now, this is a sample on how the personas would behave. So far, check whether something is inconsistent
in this structure (the attributes map to something defined in the AlephVault.WindRose.REFMAP add-on), or
whether the types are invalid.

The goal is to store the global aesthetics of a persona (profile for an account) in a specific contract
in the Polygon network.

So in order to tell what can a persona wear or not, first the lots must be defined. They're an array of
things that can only be added (never removed):

    mapping(uint128 lotId => mapping(Sex sex => mapping(TraitType traitType => mapping(uint120 traitId => uint256 colors)))) public availableTraits;

Notice how the lot id, the sex and the trait type are what's used in the AlephVault.WindRose.REFMAP
concept for `resolve(...)`, although proper strings are used there (here, there are some constants that
will be matched to a subset of those allowed strings: `TraitType` enumeration).

Now, defining a lot involves _an administrative role_ first (so there will be a concept of only-owner
or so). Also, defining the lot does not only involve that definition I said over the items but, instead,
also some involved metadata for the lot. This metadata defines:

- The type of location for the lot.
- The contents of that location.

It can be something like this:

    struct TraitsLot {
        string name; // The name of the lot.
        string url;  // The URL of the lot file or resolution mechanism.
    }

    uint128 public nextLotId = 1;

    mapping(uint128 lotId => TraitsLot) public lots;

This lot is modifiable by _an administrative role_ (never removable).

A reason on why _an administrative role_ is required is because we cannot accept any file being used here.
This is related to the licenses over the assets, which is something we cannot assess here. So it is only
an administrative task to perform. This applies to edition and to removal.

Another thing to explain is the URL. The URL is, again, mutable. And it will point to a .zip file. The idea
is that this .zip file will have the following structure:

    /
        Male/
            Arms/
            Boots/
            Chest/
            Cloth/
            Hair/   <--- Also hair tails will resolve here.
            Hat/
            LongShirt/
            Pants/
            Shirt/
            Shoulder/
            Waist/
        Female/
            Arms/
            Boots/
            Chest/
            Cloth/
            Hair/   <--- Also hair tails will resolve here.
            Hat/
            LongShirt/
            Pants/
            Shirt/
            Shoulder/
            Waist/

where all the directories are optional. This is only considered in front-end (the smart contracts only
include the URL). The URLs can be in many formats:

- http(s)://some.domain/path/to/file.zip
- ipfs://SoMEhASh
- local://somekey (e.g. local://default)

The responsibility for the maintenance and validity of the URLs is the administrative user itself. The
smart contract should never attempt to validate these values, not even in format / syntax of the URLs.
However, an empty name will tell the lot is not registered (so yes: setting the name always reverts if
the name is empty). Registering a new traits lot causes a bump the nextLotId variable by 1.

Also, first, the lot must be registered and THEN the contents of `availableTraits` can be populated.
Doing otherwise will cause a revert. Populating `availableTraits` is also reserved for the same roles
(i.e. administrative roles) that create lots.
