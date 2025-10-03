//import Foundation
//import CarPlay
//
//@MainActor
//final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
//    private var interfaceController: CPInterfaceController?
//    private var carPlayController: CarPlayController?
//
//    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
//        self.interfaceController = interfaceController
//        let engine = AudioEngineProvider.shared
//        let controller = CarPlayController(engine: engine, interfaceController: interfaceController)
//        self.carPlayController = controller
//        controller.presentRoot()
//    }
//
//    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnect interfaceController: CPInterfaceController) {
//        self.interfaceController = nil
//        self.carPlayController = nil
//    }
//}
