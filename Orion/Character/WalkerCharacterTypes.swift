import AppKit

enum WalkerFacing {
    case front
    case left
    case right
    case back
}

enum WalkerPersona {
    case orion
    case expert(ResponderExpert)
}

enum WalkerCharacterAssets {
    static let lennyAssetsDirectory = "CharacterSprites"
}
