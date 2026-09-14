//
//  Extensions.swift
//  Vapor-Telegram-Bot
//
//  Created by Евгений Старшов on 19.01.2026.
//

import  Foundation

// Расширение для округления Double
extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = Double.pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

// Расширение для преобразования даты в строку для фильтрации
extension DateFormatter {
    func stringForDatabase(from date: Date) -> String {
        self.dateFormat = "yyyy-MM-dd"
        return self.string(from: date)
    }
}

// Расширение для разбиения длинного текста
extension String {
    func splitByLength(_ length: Int) -> [String] {
        var result: [String] = []
        var currentIndex = self.startIndex
        
        while currentIndex < self.endIndex {
            let endIndex = self.index(currentIndex, offsetBy: length, limitedBy: self.endIndex) ?? self.endIndex
            result.append(String(self[currentIndex..<endIndex]))
            currentIndex = endIndex
        }
        
        return result
    }
}

