ServerEvents.recipes(event => {
    event.shaped(
        'esotericreforging:esoteric_reforging_table',
        [
            'A B',
            ' C ',
            'B A'
        ],
        {
            A: 'minecraft:andesite',
            B: 'minecraft:diorite',
            C: 'minecraft:granite'
        }
    )
    event.shaped(
        'apotheosis:uncommon_material',
        [
            'AA ',
            '   ',
            '   '
        ],
        {
            A: 'apotheosis:common_material'
        }
    )
    event.shaped(
        'apotheosis:rare_material',
        [
            'AA ',
            '   ',
            '   '
        ],
        {
            A: 'apotheosis:uncommon_material'
        }
    )
    event.shaped(
        'apotheosis:epic_material',
        [
            'AA ',
            '   ',
            '   '
        ],
        {
            A: 'apotheosis:rare_material'
        }
    )
    event.shaped(
        'apotheosis:mythic_material',
        [
            'AA ',
            '   ',
            '   '
        ],
        {
            A: 'apotheosis:epic_material'
        }
    )
     event.shaped(
        'apotheosis:ancient_material',
        [
            'AA ',
            '   ',
            '   '
        ],
        {
            A: 'apotheosis:mythic_material'
        }
    )
     event.shaped(
        'apotheotic_additions:artifact_material',
        [
            'AA ',
            '   ',
            '   '
        ],
        {
            A: 'apotheosis:ancient_material'
        }
    )
        event.shaped(
        'apotheotic_additions:heirloom_material',
        [
            'AA ',
            '   ',
            '   '
        ],
        {
            A: 'apotheotic_additions:artifact_material'
        }
    )
    event.shaped(
        'apotheotic_additions:esoteric_material',
        [
            'AA ',
            '   ',
            '   '
        ],
        {
            A: 'apotheotic_additions:heirloom_material'
        }
    )
})