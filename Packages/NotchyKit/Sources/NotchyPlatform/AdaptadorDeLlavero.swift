import Foundation
import NotchyCore
import Security

/// Secretos en el llavero de inicio de sesión, como contraseñas genéricas de Notchy. El acceso lo
/// controla la ACL del llavero, ligada a la firma de la app. No se sincroniza con iCloud.
public struct AdaptadorDeLlavero: PuertoDeSecretos {
    private let servicio: String

    public init(servicio: String = "dev.darian.notchy") {
        self.servicio = servicio
    }

    private func consulta(_ clave: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servicio,
            kSecAttrAccount as String: clave,
        ]
    }

    public func leer(_ clave: String) -> String? {
        var pedido = consulta(clave)
        pedido[kSecReturnData as String] = true
        pedido[kSecMatchLimit as String] = kSecMatchLimitOne
        var resultado: AnyObject?
        guard SecItemCopyMatching(pedido as CFDictionary, &resultado) == errSecSuccess,
            let datos = resultado as? Data
        else { return nil }
        return String(data: datos, encoding: .utf8)
    }

    public func existe(_ clave: String) -> Bool {
        var pedido = consulta(clave)
        pedido[kSecReturnAttributes as String] = true
        pedido[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(pedido as CFDictionary, nil) == errSecSuccess
    }

    public func guardar(_ valor: String?, en clave: String) throws {
        let base = consulta(clave)
        guard let valor, !valor.isEmpty else {
            let estado = SecItemDelete(base as CFDictionary)
            guard estado == errSecSuccess || estado == errSecItemNotFound else {
                throw NotchyError.datos("No se pudo borrar el secreto del llavero (\(estado))")
            }
            return
        }
        let datos = Data(valor.utf8)
        let cambios: [String: Any] = [kSecValueData as String: datos]
        var estado = SecItemUpdate(base as CFDictionary, cambios as CFDictionary)
        if estado == errSecItemNotFound {
            var nuevo = base
            nuevo[kSecValueData as String] = datos
            estado = SecItemAdd(nuevo as CFDictionary, nil)
        }
        guard estado == errSecSuccess else {
            throw NotchyError.datos("No se pudo guardar el secreto en el llavero (\(estado))")
        }
    }
}
