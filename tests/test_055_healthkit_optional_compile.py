"""Regression test for the real Xcode 65 error at HealthReader.swift:32/33/64/65.

On the iOS SDK HKObjectType.characteristicType(forIdentifier:) returns
HKCharacteristicType?, which cannot be inserted into Set<HKObjectType> directly.
Tests only inspect the actual source; they do not claim an iOS build passed.
"""
from pathlib import Path
import re
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / 'ios' / 'Sources' / 'HealthReader.swift')

class OptionalHealthKitCharacteristicsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.swift = SOURCE.read_text(encoding='utf-8')

    def test_no_optional_characteristic_type_inserted_directly(self):
        self.assertNotRegex(self.swift, r'types\.insert\s*\(\s*HKObjectType\.characteristicType\s*\(')

    def test_no_optional_characteristic_type_in_set_literal(self):
        self.assertNotRegex(self.swift, r'var\s+types\s*:\s*Set<HKObjectType>\s*=\s*\[\s*HKObjectType\.characteristicType')

    def test_authorize_has_safe_unwrapping_for_both_characteristics(self):
        authorize = self.swift.split('func authorize(', 1)[1].split('func authorizeProfile(', 1)[0]
        for identifier in ('dateOfBirth', 'biologicalSex'):
            self.assertRegex(authorize, rf'if let \w+ = HKObjectType\.characteristicType\(forIdentifier: \.{identifier}\)')

    def test_authorize_profile_has_safe_unwrapping_for_both_characteristics(self):
        profile = self.swift.split('func authorizeProfile(', 1)[1].split('func samplePage(', 1)[0]
        self.assertIn('var types = Set<HKObjectType>()', profile)
        for identifier in ('dateOfBirth', 'biologicalSex'):
            self.assertRegex(profile, rf'if let \w+ = HKObjectType\.characteristicType\(forIdentifier: \.{identifier}\)')

if __name__ == '__main__':
    unittest.main()
