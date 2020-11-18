package bake

command: {
  image: #Dubo & {
    args: {
      BUILD_TITLE: "CoreDNS with Lego"
      BUILD_DESCRIPTION: "A dubo image for CoreDNS based on \(args.DEBOOTSTRAP_SUITE) (\(args.DEBOOTSTRAP_DATE))"
    }
  }
}
