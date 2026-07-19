So this ecosystem is a set of smart contracts deployed in Polygon mainnet (137) and Amoy testnet (80002). Of course,
users will be able to deploy this as well in their local networks.

The underlying idea is to tie an aesthetic to each address to define some sort of Persona linked to the address.
So a central record will exist to hold each Persona created for an address with something like this:

    // A trait is an element to render. It can be a cloth, a body, a hair, ...
    // It should be understood that lotId being 0 means nothing is selected.
    // The first lotId is 1, and will per-deployment (i.e. per-data) stand for
    // REFMAP. Others will / might be added later.
    struct Trait {
        uint128 lotId;
        uint120 itemId;
        uint8 color;
    }

    // The sex.
    enum Sex { Male, Female }

    // The body color. Male and female have access to images of the same values.
    enum Body { Black, Orange, White, Purple, Yellow, Red, Green, Blue }

    // Whether the character uses simple or standard clothes.
    enum ClothType { Standard, Simple }

    // The rendering of a persona (visual aspects of an account).
    struct Persona {
        string name; // The name will be unique among all the personas.
                     // Even perhaps limiting the ability to change this value?
                     // Even perhaps limiting this field to something like [a-z0-9_]+.
        Sex sex;
        Body body;
        Trait body;
        Trait hair;
        Trait hairTail; // Yes, the hair tail goes separate.
        Trait necklace; // The necklace can come in different tones.
        Trait hat;      // Same for the hat.
        // Left and right hand are not included.
        ClothType clothType;
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
in this structure (the attributes map to something defined in the AlephVault.WindRose.REFMAP add-on).

The goal is to store the global aesthetics of a persona (profile for an account) in a specific contract
in the Polygon network.

So in order to tell what can a persona wear or not, first the lots must be defined:
